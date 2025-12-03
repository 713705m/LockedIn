import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Seance.date) private var seances: [Seance]
    
    @State private var selectedPeriod: StatsPeriod = .deuxMois
    @State private var stravaConnected = false
    @State private var showingStravaAuth = false
    
    // Données pour les graphiques (simulées pour l'instant)
    @State private var weeklyData: [WeeklyStats] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Période sélection
                    Picker("Période", selection: $selectedPeriod) {
                        ForEach(StatsPeriod.allCases, id: \.self) { period in
                            Text(period.rawValue).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    // MARK: - Connexion Strava
                    if !stravaConnected {
                        StravaConnectionCard {
                            showingStravaAuth = true
                        }
                        .padding(.horizontal)
                    }
                    
                    // MARK: - Résumé
                    SummaryCardsView(seances: seances, period: selectedPeriod)
                        .padding(.horizontal)
                    
                    // MARK: - Graphique Volume
                    VolumeChartView(data: weeklyData)
                        .padding(.horizontal)
                    
                    // MARK: - Graphique Intensité
                    IntensiteChartView(seances: filteredSeances)
                        .padding(.horizontal)
                    
                    // MARK: - Répartition par sport
                    SportDistributionView(seances: filteredSeances)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Statistiques")
            .onAppear {
                generateWeeklyData()
            }
            .onChange(of: selectedPeriod) { _, _ in
                generateWeeklyData()
            }
            .sheet(isPresented: $showingStravaAuth) {
                StravaAuthView(isConnected: $stravaConnected)
            }
        }
    }
    
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
        
        return seances.filter { $0.date >= startDate && $0.date <= now && $0.statut == .effectue }
    }
    
    private func generateWeeklyData() {
        // Génère des données par semaine à partir des séances
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
}

// MARK: - Enums & Models

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

// MARK: - Strava Connection Card

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
                    Text("Synchronise tes activités automatiquement")
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

// MARK: - Summary Cards

struct SummaryCardsView: View {
    let seances: [Seance]
    let period: StatsPeriod
    
    private var effectuees: [Seance] {
        seances.filter { $0.statut == .effectue }
    }
    
    private var totalMinutes: Int {
        effectuees.reduce(0) { $0 + $1.dureeMinutes }
    }
    
    private var totalKm: Double {
        effectuees.compactMap { $0.distanceKm }.reduce(0, +)
    }
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            StatCard(
                title: "Séances",
                value: "\(effectuees.count)",
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
                icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
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

// MARK: - Volume Chart

struct VolumeChartView: View {
    let data: [WeeklyStats]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volume hebdomadaire")
                .font(.headline)
            
            if data.isEmpty {
                Text("Pas encore de données")
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
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(Int(hours))h")
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Intensite Chart

struct IntensiteChartView: View {
    let seances: [Seance]
    
    private var intensiteData: [(Intensite, Int)] {
        let grouped = Dictionary(grouping: seances) { $0.intensite }
        return Intensite.allCases.map { intensite in
            (intensite, grouped[intensite]?.count ?? 0)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Répartition par intensité")
                .font(.headline)
            
            if seances.isEmpty {
                Text("Pas encore de données")
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
                    .foregroundStyle(by: .value("Intensité", item.0.rawValue))
                    .cornerRadius(4)
                }
                .frame(height: 150)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Sport Distribution

struct SportDistributionView: View {
    let seances: [Seance]
    
    private var sportData: [(String, Int)] {
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
            return "\(hours)h\(String(format: "%02d", mins))"
        }
        return "\(mins)min"
    }
}

// MARK: - Strava Auth View (placeholder)

struct StravaAuthView: View {
    @Binding var isConnected: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.orange)
                
                Text("Connexion à Strava")
                    .font(.title)
                    .bold()
                
                Text("Cette fonctionnalité nécessite un backend pour gérer l'authentification OAuth de manière sécurisée.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Synchronisation automatique", systemImage: "arrow.triangle.2.circlepath")
                    Label("Historique complet", systemImage: "clock.arrow.circlepath")
                    Label("Statistiques détaillées", systemImage: "chart.bar.fill")
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                Spacer()
                
                Text("À implémenter avec le backend Vercel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    StatsView()
        .modelContainer(for: [Athlete.self, Seance.self, ChatMessage.self], inMemory: true)
}
