import Foundation
import AuthenticationServices

// MARK: - Strava Service

class StravaService: NSObject, ObservableObject {
    static let shared = StravaService()
    
    // ✅ URL de ton backend Vercel
    private let backendURL = "https://lockedin-backend.vercel.app"
    
    // Tokens stockés dans le Keychain (simplifié ici avec UserDefaults)
    @Published var isConnected: Bool = false
    @Published var athleteId: String?
    
    private var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "strava_access_token") }
        set { UserDefaults.standard.set(newValue, forKey: "strava_access_token") }
    }
    
    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "strava_refresh_token") }
        set { UserDefaults.standard.set(newValue, forKey: "strava_refresh_token") }
    }
    
    private var tokenExpiresAt: Date? {
        get {
            let timestamp = UserDefaults.standard.double(forKey: "strava_expires_at")
            return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "strava_expires_at")
        }
    }
    
    override init() {
        super.init()
        isConnected = accessToken != nil
        athleteId = UserDefaults.standard.string(forKey: "strava_athlete_id")
    }
    
    // MARK: - OAuth Flow
    
    /// Démarre le flow OAuth Strava
    func startOAuth() async throws -> URL {
        guard let url = URL(string: "\(backendURL)/api/strava/auth") else {
            throw StravaError.invalidURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let authURLString = json["authUrl"] as? String,
              let authURL = URL(string: authURLString) else {
            throw StravaError.invalidResponse
        }
        
        return authURL
    }
    
    /// Traite le callback OAuth (appelé depuis le deep link)
    func handleCallback(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return }
        
        var params: [String: String] = [:]
        for item in queryItems {
            params[item.name] = item.value
        }
        
        if let accessToken = params["access_token"],
           let refreshToken = params["refresh_token"],
           let expiresAtString = params["expires_at"],
           let expiresAt = Double(expiresAtString) {
            
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.tokenExpiresAt = Date(timeIntervalSince1970: expiresAt)
            self.athleteId = params["athlete_id"]
            
            if let athleteId = params["athlete_id"] {
                UserDefaults.standard.set(athleteId, forKey: "strava_athlete_id")
            }
            
            DispatchQueue.main.async {
                self.isConnected = true
            }
        }
    }
    
    // MARK: - Token Management
    
    /// Vérifie et rafraîchit le token si nécessaire// Dans StravaService.swift
    
    private func getValidToken() async throws -> String {
        // 1. Vérifier qu'on a un token
        guard let currentToken = accessToken else {
            throw StravaError.notConnected
        }
        
        // 2. Vérifier s'il expire bientôt (dans les 5 minutes)
        if let expiresAt = tokenExpiresAt, expiresAt < Date().addingTimeInterval(300) {
            print("🔄 Token expiré ou presque, rafraîchissement...")
            try await refreshAccessToken()
            
            // Après le refresh, on renvoie le tout nouveau token
            guard let newToken = accessToken else {
                throw StravaError.tokenExpired
            }
            return newToken
        }
        
        // 3. Sinon, le token actuel est bon
        return currentToken
    }
    
    /// Rafraîchit le token d'accès
    private func refreshAccessToken() async throws {
        guard let refreshToken = refreshToken else {
            throw StravaError.notConnected
        }
        
        guard let url = URL(string: "\(backendURL)/api/strava/refresh") else {
            throw StravaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "refresh_token": refreshToken
        ])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StravaError.tokenRefreshFailed
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String,
              let newRefreshToken = json["refresh_token"] as? String,
              let expiresAt = json["expires_at"] as? Double else {
            throw StravaError.invalidResponse
        }
        
        self.accessToken = newAccessToken
        self.refreshToken = newRefreshToken
        self.tokenExpiresAt = Date(timeIntervalSince1970: expiresAt)
    }
    
    // MARK: - API Calls
    
    /// Récupère les activités des X derniers jours
    func getActivities(days: Int = 60, perPage: Int = 50) async throws -> [StravaActivity] {
        let token = try await getValidToken()
        
        let afterTimestamp = Int(Date().addingTimeInterval(TimeInterval(-days * 24 * 60 * 60)).timeIntervalSince1970)
        
        guard var urlComponents = URLComponents(string: "\(backendURL)/api/strava/activities") else {
            throw StravaError.invalidURL
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "after", value: String(afterTimestamp)),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]
        
        guard let url = urlComponents.url else {
            throw StravaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            // Token expiré, essayer de rafraîchir et réessayer
            try await refreshAccessToken()
            return try await getActivities(days: days, perPage: perPage)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw StravaError.apiError("Status \(httpResponse.statusCode)")
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let activitiesData = json["activities"] as? [[String: Any]] else {
            throw StravaError.invalidResponse
        }
        
        return activitiesData.compactMap { StravaActivity(from: $0) }
    }
    
    // MARK: - Disconnect
    
    func disconnect() {
        accessToken = nil
        refreshToken = nil
        tokenExpiresAt = nil
        athleteId = nil
        UserDefaults.standard.removeObject(forKey: "strava_athlete_id")
        
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}

// MARK: - Models

struct StravaActivity: Identifiable {
    let id: Int
    let name: String
    let type: String
    let sportType: String?
    let date: Date
    let distanceKm: Double
    let movingTime: Int // secondes
    let pace: String?
    let averageHeartrate: Int?
    let totalElevationGain: Double?
    let calories: Int?
    
    init?(from dict: [String: Any]) {
        guard let id = dict["id"] as? Int,
              let name = dict["name"] as? String,
              let type = dict["type"] as? String,
              let dateString = dict["date"] as? String,
              let distanceKmString = dict["distance_km"] as? String,
              let distanceKm = Double(distanceKmString),
              let movingTime = dict["moving_time"] as? Int else {
            return nil
        }
        
        self.id = id
        self.name = name
        self.type = type
        self.sportType = dict["sport_type"] as? String
        self.distanceKm = distanceKm
        self.movingTime = movingTime
        self.pace = dict["pace_per_km"] as? String
        self.averageHeartrate = dict["average_heartrate"] as? Int
        self.totalElevationGain = dict["total_elevation_gain"] as? Double
        self.calories = dict["calories"] as? Int
        
        // Parse la date ISO8601
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: dateString) {
            self.date = date
        } else {
            // Essaie sans les fractions de seconde
            formatter.formatOptions = [.withInternetDateTime]
            self.date = formatter.date(from: dateString) ?? Date()
        }
    }
    
    var durationFormatted: String {
        let hours = movingTime / 3600
        let minutes = (movingTime % 3600) / 60
        if hours > 0 {
            return "\(hours)h\(String(format: "%02d", minutes))"
        }
        return "\(minutes) min"
    }
    
    var typeEmoji: String {
        switch type.lowercased() {
        case "run": return "🏃"
        case "ride": return "🚴"
        case "swim": return "🏊"
        case "walk": return "🚶"
        case "hike": return "🥾"
        default: return "🏅"
        }
    }
}

// MARK: - Errors

enum StravaError: LocalizedError {
    case invalidURL
    case invalidResponse
    case notConnected
    case tokenExpired
    case tokenRefreshFailed
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL invalide"
        case .invalidResponse:
            return "Réponse invalide"
        case .notConnected:
            return "Non connecté à Strava"
        case .tokenExpired:
            return "Session expirée"
        case .tokenRefreshFailed:
            return "Impossible de rafraîchir la session"
        case .apiError(let message):
            return "Erreur Strava: \(message)"
        }
    }
}
