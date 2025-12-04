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
                    
                    SpeedEvolutionChart(seances: filteredSeances)
                        .padding(.horizontal)
                    
                    SportAveragesTableView(seances: filteredSeances)
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

struct SpeedEvolutionChart: View {
    let seances: [Seance]
    
    // État pour le choix du sport
    @State private var selectedSport = "Course"
    let sports = ["Course", "Vélo", "Natation"]
    
    // Structure interne pour les points du graph
    struct DataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }
    
    // Calcul des données selon le sport
    private var chartData: [DataPoint] {
        let filtered = seances.filter {
            $0.sport == selectedSport &&
            $0.statut == .effectue &&
            ($0.distanceKm ?? 0) > 0 &&
            $0.dureeMinutes > 0
        }.sorted { $0.date < $1.date }
        
        return filtered.map { seance in
            let dist = seance.distanceKm ?? 0
            let mins = Double(seance.dureeMinutes)
            var val: Double = 0
            
            switch selectedSport {
            case "Course":
                // min/km
                val = mins / dist
            case "Natation":
                // min/100m (distance * 10 = nbr de 100m)
                val = mins / (dist * 10)
            case "Vélo":
                // km/h
                val = dist / (mins / 60.0)
            default:
                val = 0
            }
            
            return DataPoint(date: seance.date, value: val)
        }
    }
    
    private var yAxisLabel: String {
        switch selectedSport {
        case "Course": return "Allure (min/km)"
        case "Natation": return "Allure (min/100m)"
        default: return "Vitesse (km/h)"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header avec Titre et Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Évolution Performance")
                    .font(.headline)
                
                Picker("Sport", selection: $selectedSport) {
                    ForEach(sports, id: \.self) { sport in
                        Text(sport).tag(sport)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            if chartData.isEmpty {
                ContentUnavailableView {
                    Label("Pas assez de données", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Effectue des séances de \(selectedSport.lowercased()) pour voir ta progression.")
                }
                .frame(height: 220)
            } else {
                Chart(chartData) { item in
                    // Ligne
                    LineMark(
                        x: .value("Date", item.date),
                        y: .value("Vitesse", item.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(sportColor)
                    
                    // Points
                    PointMark(
                        x: .value("Date", item.date),
                        y: .value("Vitesse", item.value)
                    )
                    .foregroundStyle(sportColor)
                    
                    // Zone dégradée
                    AreaMark(
                        x: .value("Date", item.date),
                        y: .value("Vitesse", item.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [sportColor.opacity(0.3), sportColor.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(formatAxisValue(doubleValue))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(format: .dateTime.day().month())
                }
                .frame(height: 220)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut, value: selectedSport) // Animation fluide au changement
    }
    
    // MARK: - Helpers
    
    private var sportColor: Color {
        switch selectedSport {
        case "Course": return .blue
        case "Vélo": return .green
        case "Natation": return .cyan
        default: return .blue
        }
    }
    
    // Formatteur pour convertir les décimales (5.5) en temps (5'30") si besoin
    private func formatAxisValue(_ value: Double) -> String {
        if selectedSport == "Vélo" {
            // Pour le vélo, on affiche juste le chiffre (km/h)
            return String(format: "%.0f", value)
        } else {
            // Pour Course/Natation, on convertit en min'sec"
            let minutes = Int(value)
            let seconds = Int((value - Double(minutes)) * 60)
            return String(format: "%d'%02d\"", minutes, seconds)
        }
    }
}
struct SportAveragesTableView: View {
    let seances: [Seance]
    
    // État pour le filtre du graphique
    @State private var selectedSportGraph = "Course"
    let sportsDisponibles = ["Course", "Vélo", "Natation", "Autre"]
    
    // MARK: - Logique Données Graphique
    
    private var graphData: [Seance] {
        seances.filter { seance in
            if selectedSportGraph == "Autre" {
                // Tout ce qui n'est pas les 3 sports principaux
                return !["Course", "Vélo", "Natation", "Run", "Ride", "Swim"].contains(seance.sport)
            }
            // Filtre par sport (avec compatibilité des noms anglais Strava si besoin)
            return seance.sport == selectedSportGraph ||
                   (selectedSportGraph == "Vélo" && seance.sport == "Ride") ||
                   (selectedSportGraph == "Course" && seance.sport == "Run") ||
                   (selectedSportGraph == "Natation" && seance.sport == "Swim")
        }.sorted { $0.date < $1.date }
    }
    
    // Fonction pour obtenir la valeur Y (Distance ou Durée) selon le sport
    private func getValue(for seance: Seance) -> Double {
        switch selectedSportGraph {
        case "Natation":
            // Distance en Mètres
            return (seance.distanceKm ?? 0) * 1000
        case "Course", "Vélo":
            // Distance en Km
            return seance.distanceKm ?? 0
        default:
            // Durée en Minutes pour le reste
            return Double(seance.dureeMinutes)
        }
    }
    
    private var yAxisLabel: String {
        switch selectedSportGraph {
        case "Natation": return "Distance (m)"
        case "Course", "Vélo": return "Distance (km)"
        default: return "Durée (min)"
        }
    }
    
    // MARK: - Calculs Moyennes (Ton code existant)
    
    // Séances de course avec distance
    private var courseSeances: [Seance] {
        seances.filter { $0.sport == "Course" && $0.distanceKm != nil && $0.distanceKm! > 0 }
    }
    
    // Séances de natation
    private var natationSeances: [Seance] {
        seances.filter { $0.sport == "Natation" }
    }
    
    // Moyennes Course
    private var courseStats: (distanceAvg: Double, vitesseAvg: Double, count: Int) {
        guard !courseSeances.isEmpty else { return (0, 0, 0) }
        
        let totalDistance = courseSeances.compactMap { $0.distanceKm }.reduce(0, +)
        let avgDistance = totalDistance / Double(courseSeances.count)
        
        var totalVitesse: Double = 0
        var vitesseCount = 0
        
        for seance in courseSeances {
            if let distance = seance.distanceKm, seance.dureeMinutes > 0 {
                let heures = Double(seance.dureeMinutes) / 60.0
                let vitesse = distance / heures
                totalVitesse += vitesse
                vitesseCount += 1
            }
        }
        
        let avgVitesse = vitesseCount > 0 ? totalVitesse / Double(vitesseCount) : 0
        
        return (avgDistance, avgVitesse, courseSeances.count)
    }
    
    // Moyennes Natation
    private var natationStats: (distanceAvgMetres: Double, tempsAvgMin: Int, count: Int) {
        guard !natationSeances.isEmpty else { return (0, 0, 0) }
        
        let totalDistanceMetres = natationSeances.compactMap { $0.distanceKm }.reduce(0, +) * 1000
        let avgDistanceMetres = totalDistanceMetres / Double(natationSeances.count)
        
        let totalMinutes = natationSeances.reduce(0) { $0 + $1.dureeMinutes }
        let avgMinutes = totalMinutes / natationSeances.count
        
        return (avgDistanceMetres, avgMinutes, natationSeances.count)
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            
            // 1. Titre et Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Progression & Moyennes")
                    .font(.headline)
                
                Picker("Sport", selection: $selectedSportGraph) {
                    ForEach(sportsDisponibles, id: \.self) { sport in
                        Text(sport).tag(sport)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal)
            
            // 2. Graphique (Line + Points)
            if !graphData.isEmpty {
                Chart(graphData) { seance in
                    // Ligne
                    LineMark(
                        x: .value("Date", seance.date),
                        y: .value("Valeur", getValue(for: seance))
                    )
                    .foregroundStyle(sportColor(selectedSportGraph))
                    .interpolationMethod(.catmullRom) // Courbe lissée
                    
                    // Points
                    PointMark(
                        x: .value("Date", seance.date),
                        y: .value("Valeur", getValue(for: seance))
                    )
                    .foregroundStyle(sportColor(selectedSportGraph))
                }
                .chartYAxisLabel(yAxisLabel)
                .chartXAxis {
                    AxisMarks(format: .dateTime.day().month())
                }
                .frame(height: 220)
                .padding(.horizontal)
            } else {
                ContentUnavailableView {
                    Label("Pas de données", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Aucune séance de \(selectedSportGraph.lowercased()) sur cette période.")
                }
                .frame(height: 220)
            }
            
            Divider().padding(.horizontal)
            
            // 3. Tableaux des Moyennes (Ton code original)
            VStack(alignment: .leading, spacing: 12) {
                Text("Moyennes globales")
                    .font(.headline)
                    .padding(.horizontal)
                
                // Tableau Course
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundStyle(.blue)
                        Text("Course")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(courseStats.count) séances")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1))
                    
                    Divider()
                    
                    if courseStats.count > 0 {
                        statRow(label: "Distance moyenne", value: String(format: "%.1f km", courseStats.distanceAvg))
                        Divider()
                        statRow(label: "Vitesse moyenne", value: String(format: "%.1f km/h", courseStats.vitesseAvg))
                        Divider()
                        statRow(label: "Allure moyenne", value: formatPace(kmPerHour: courseStats.vitesseAvg))
                    } else {
                        Text("Pas de données course")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
                
                // Tableau Natation
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "figure.pool.swim")
                            .foregroundStyle(.cyan)
                        Text("Natation")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Spacer()
                        Text("\(natationStats.count) séances")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.cyan.opacity(0.1))
                    
                    Divider()
                    
                    if natationStats.count > 0 {
                        statRow(label: "Distance moyenne", value: String(format: "%.0f m", natationStats.distanceAvgMetres))
                        Divider()
                        statRow(label: "Durée moyenne", value: formatDuration(natationStats.tempsAvgMin))
                        Divider()
                        statRow(label: "Allure /100m", value: formatSwimPace(metres: natationStats.distanceAvgMetres, minutes: natationStats.tempsAvgMin))
                    } else {
                        Text("Pas de données natation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Helpers
    
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private func sportColor(_ sport: String) -> Color {
        switch sport {
        case "Course": return .blue
        case "Vélo": return .green
        case "Natation": return .cyan
        default: return .orange
        }
    }
    
    // Formatters existants
    private func formatPace(kmPerHour: Double) -> String {
        guard kmPerHour > 0 else { return "--'--" }
        let minPerKm = 60.0 / kmPerHour
        let minutes = Int(minPerKm)
        let seconds = Int((minPerKm - Double(minutes)) * 60)
        return String(format: "%d'%02d /km", minutes, seconds)
    }
    
    private func formatSwimPace(metres: Double, minutes: Int) -> String {
        guard metres > 0 && minutes > 0 else { return "--:--" }
        let totalSeconds = Double(minutes * 60)
        let secondsPer100m = (totalSeconds / metres) * 100
        let mins = Int(secondsPer100m) / 60
        let secs = Int(secondsPer100m) % 60
        return String(format: "%d:%02d /100m", mins, secs)
    }
    
    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h\(String(format: "%02d", mins))"
        }
        return "\(mins) min"
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
