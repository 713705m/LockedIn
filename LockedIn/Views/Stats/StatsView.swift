import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    // MARK: - Propriétés
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) var openURL
    
    // Récupération des séances depuis SwiftData
    @Query(sort: \Seance.date, order: .reverse) private var seances: [Seance]
    
    // Service Strava (Singleton)
    @ObservedObject private var stravaService = StravaService.shared
    
    // États locaux
    @State private var selectedPeriod: StatsPeriod = .deuxMois
    @State private var isSyncing = false
    @State private var weeklyData: [WeeklyStats] = []
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 1. Sélecteur de période
                    Picker("Période", selection: $selectedPeriod) {
                        ForEach(StatsPeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                
                    // 2. Carte de connexion (Visible seulement si non connecté)
                    if !stravaService.isConnected {
                        StravaConnectionCard {
                            connectStrava()
                        }
                        .padding(.horizontal)
                    }
                    
                    // 3. Indicateur de chargement pendant la sync
                    if isSyncing {
                        HStack {
                            ProgressView()
                            Text("Synchronisation avec Strava...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // 4. Résumé (KPIs)
                    SummaryCardsView(seances: filteredSeances, period: selectedPeriod)
                        .padding(.horizontal)
                    
                    // 5. Graphiques
                    VolumeChartView(data: weeklyData)
                        .padding(.horizontal)
                    
                    IntensiteChartView(seances: filteredSeances)
                        .padding(.horizontal)
                    
                    SportDistributionView(seances: filteredSeances)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Statistiques")
            // MARK: - Cycle de vie & Sync
            .onAppear {
                generateWeeklyData()
            }
            .onChange(of: selectedPeriod) { _, _ in
                generateWeeklyData()
            }
            // Tente une sync au démarrage de la vue si connecté
            .task {
                if stravaService.isConnected {
                    await syncStravaActivities()
                }
            }
            // Réagit si la connexion change (ex: retour de Safari après OAuth)
            .onChange(of: stravaService.isConnected) { _, isConnected in
                if isConnected {
                    Task { await syncStravaActivities() }
                }
            }
        }
    }
    
    // MARK: - Logique Métier
    
    private var filteredSeances: [Seance] {
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date
        
        switch selectedPeriod {
        case .unMois:
            startDate = calendar.date(byAdding: .month, value: -1, to: now)!
        case .deuxMois:
            startDate = calendar.date(byAdding: .month, value: -2, to: now)!
        case .troisMois:
            startDate = calendar.date(byAdding: .month, value: -3, to: now)!
        }
        
        // On filtre par date ET statut (si ton modèle a un statut)
        return seances.filter {
            $0.date >= startDate &&
            $0.date <= now &&
            $0.statut == .effectue
        }
    }
    
    private func generateWeeklyData() {
        let calendar = Calendar.current
        let now = Date()
        let weeksCount = selectedPeriod.weeks
        
        weeklyData = (0..<weeksCount).reversed().map { weekOffset in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now)!
            let weekSeances = seances.filter { seance in
                calendar.isDate(seance.date, equalTo: weekStart, toGranularity: .weekOfYear) &&
                seance.statut == .effectue
            }
            
            let totalMinutes = weekSeances.reduce(0) { $0 + $1.dureeMinutes }
            let totalKm = weekSeances.compactMap { $0.distanceKm }.reduce(0, +)
            
            return WeeklyStats(
                weekStart: weekStart,
                totalMinutes: totalMinutes,
                totalKm: totalKm,
                seancesCount: weekSeances.count
            )
        }
    }
    
    // MARK: - Actions Strava
    
    private func connectStrava() {
        Task {
            do {
                let url = try await stravaService.startOAuth()
                openURL(url)
            } catch {
                print("Erreur de connexion : \(error)")
            }
        }
    }
    
    // MARK: - Synchronisation Strava

    // 1. Ajout du mot clé 'async' ici pour corriger l'erreur de compilation
    private func syncStravaActivities() async {
        guard stravaService.isConnected else { return }
        
        // On passe sur le MainActor pour modifier l'UI (isSyncing) et SwiftData
        await MainActor.run { isSyncing = true }
        
        do {
            print("🔄 Début de la synchronisation...")
            
            // Récupération des données depuis ton backend
            let activities = try await stravaService.getActivities(days: 30)
            
            await MainActor.run {
                var newCount = 0
                
                for activity in activities {
                    // 2. Vérification d'existence plus robuste
                    // On vérifie d'abord via l'ID Strava (String), sinon par date
                    let stravaIdString = String(activity.id)
                    
                    let exists = seances.contains { seance in
                        seance.stravaActivityId == stravaIdString ||
                        Calendar.current.isDate(seance.date, equalTo: activity.date, toGranularity: .minute)
                    }
                    
                    if !exists {
                        // 3. Mapping précis vers ton initialiseur Seance.swift
                        
                        // Conversion du sport (ex: "Run" -> "Course")
                        let sportTraduit = mapStravaSportToApp(stravaType: activity.type)
                        
                        // Création de la séance avec l'init obligatoire
                        let nouvelleSeance = Seance(
                            date: activity.date,
                            type: .endurance, // Par défaut, Strava ne donne pas le type précis (VMA, Seuil...), on met Endurance
                            sport: sportTraduit,
                            dureeMinutes: Int(activity.movingTime / 60),
                            description: activity.name, // Mappe vers description_
                            intensite: .modere // Par défaut
                        )
                        
                        // Remplissage des champs optionnels et d'état
                        nouvelleSeance.statut = .effectue
                        nouvelleSeance.distanceKm = activity.distanceKm // Ton backend renvoie déjà distance_km calculé ou activity.distance / 1000
                        nouvelleSeance.stravaActivityId = stravaIdString
                        
                        // Si ton modèle backend renvoie la FC (average_heartrate)
                        if let heartRate = activity.averageHeartrate {
                            nouvelleSeance.fcMoyenne = Int(heartRate)
                        }
                        
                        modelContext.insert(nouvelleSeance)
                        newCount += 1
                    }
                }
                print("✅ Fin de sync : \(newCount) nouvelles séances ajoutées")
                
                // On met à jour les graphiques
                generateWeeklyData()
                isSyncing = false
            }
        } catch {
            print("❌ Erreur de synchronisation : \(error)")
            await MainActor.run { isSyncing = false }
        }
    }
    
    // Petite fonction utilitaire pour traduire les sports Strava
    private func mapStravaSportToApp(stravaType: String) -> String {
        switch stravaType {
        case "Run": return "Course"
        case "Ride", "VirtualRide", "EBikeRide": return "Vélo"
        case "Swim": return "Natation"
        case "WeightTraining", "Workout": return "Renforcement"
        case "Yoga": return "Étirements"
        default: return "Course" // Valeur par défaut si inconnu
        }
    }
}

// MARK: - Enums & Models Helper

enum StatsPeriod: String, CaseIterable {
    case unMois = "1 mois"
    case deuxMois = "2 mois"
    case troisMois = "3 mois"
    
    var weeks: Int {
        switch self {
        case .unMois: return 4
        case .deuxMois: return 8
        case .troisMois: return 12
        }
    }
}

struct WeeklyStats: Identifiable {
    let id = UUID()
    let weekStart: Date
    let totalMinutes: Int
    let totalKm: Double
    let seancesCount: Int
    
    var weekLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: weekStart)
    }
    
    var heures: Double {
        Double(totalMinutes) / 60.0
    }
}

// MARK: - Subviews

struct StravaConnectionCard: View {
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "link.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading) {
                    Text("Connecte Strava")
                        .font(.headline)
                    Text("Synchronise tes activités")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Connecter", action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SummaryCardsView: View {
    let seances: [Seance]
    let period: StatsPeriod
    
    private var totalMinutes: Int {
        seances.reduce(0) { $0 + $1.dureeMinutes }
    }
    
    private var totalKm: Double {
        seances.compactMap { $0.distanceKm }.reduce(0, +)
    }
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            StatCard(
                title: "Séances",
                value: "\(seances.count)",
                icon: "figure.run",
                color: .blue
            )
            
            StatCard(
                title: "Volume",
                value: formatDuration(totalMinutes),
                icon: "clock.fill",
                color: .green
            )
            
            StatCard(
                title: "Distance",
                value: String(format: "%.0f km", totalKm),
                icon: "map.fill",
                color: .orange
            )
        }
    }
    
    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h\(String(format: "%02d", mins))"
        }
        return "\(mins)min"
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title2)
                .bold()
            
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct VolumeChartView: View {
    let data: [WeeklyStats]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volume hebdomadaire")
                .font(.headline)
            
            if data.isEmpty {
                Text("Pas de données sur la période")
                    .foregroundStyle(.secondary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(data) { week in
                    BarMark(
                        x: .value("Semaine", week.weekLabel),
                        y: .value("Heures", week.heures)
                    )
                    .foregroundStyle(.blue.gradient)
                    .cornerRadius(4)
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct IntensiteChartView: View {
    let seances: [Seance]
    
    // Assure-toi que ton modèle Seance a bien une propriété 'intensite' qui est Hashable/Enum
    private var intensiteData: [(String, Int)] {
        let grouped = Dictionary(grouping: seances) { $0.intensite.rawValue } // ou .description
        return grouped.map { ($0.key, $0.value.count) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Répartition par intensité")
                .font(.headline)
            
            if seances.isEmpty {
                Text("Pas assez de données")
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(intensiteData, id: \.0) { item in
                    SectorMark(
                        angle: .value("Count", item.1),
                        innerRadius: .ratio(0.5),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Intensité", item.0))
                }
                .frame(height: 150)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SportDistributionView: View {
    let seances: [Seance]
    
    private var sportData: [(String, Int)] {
        // Suppose que seance.sport est une String ou a une propriété rawValue
        let grouped = Dictionary(grouping: seances) { $0.sport }
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.dureeMinutes }) }
            .sorted { $0.1 > $1.1 }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Temps par sport")
                .font(.headline)
            
            if sportData.isEmpty {
                Text("Pas encore de données")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sportData, id: \.0) { sport, minutes in
                    HStack {
                        Text(sport)
                        Spacer()
                        Text(formatDuration(minutes))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)"
        }
        return "\(mins)min"
    }
}

#Preview {
    StatsView()
        .modelContainer(for: [Seance.self], inMemory: true)
}
