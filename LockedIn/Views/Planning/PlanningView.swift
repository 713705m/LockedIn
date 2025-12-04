import SwiftUI
import SwiftData

struct PlanningView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Seance.date) private var seances: [Seance]
    
    @State private var selectedWeek = 0
    @State private var showingAddSeance = false
    @State private var selectedSeance: Seance?
    
    // Dates des 3 prochaines semaines (étendu pour voir plus loin)
    private var weeks: [(String, Date, Date)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        return (0..<3).map { weekOffset in
            let weekStart = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: today)!
            let actualStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart))!
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: actualStart)!
            
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.dateFormat = "d MMM"
            
            let label: String
            switch weekOffset {
            case 0: label = "Cette semaine"
            default: label = "S+\(weekOffset)"
            }
            
            return (label, actualStart, weekEnd)
        }
    }
    
    // Séances filtrées pour la semaine sélectionnée
    private var seancesSemaine: [Seance] {
        guard selectedWeek < weeks.count else { return [] }
        let (_, start, end) = weeks[selectedWeek]
        
        // Inclure la fin de journée du dernier jour
        let calendar = Calendar.current
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
        
        return seances.filter { seance in
            seance.date >= start && seance.date <= endOfDay
        }
    }
    
    // Groupées par jour
    private var seancesParJour: [(String, [Seance])] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d"
        
        let grouped = Dictionary(grouping: seancesSemaine) { seance in
            calendar.startOfDay(for: seance.date)
        }
        
        return grouped.keys.sorted().map { date in
            (formatter.string(from: date).capitalized, grouped[date] ?? [])
        }
    }
    
    // Stats de la semaine
    private var statsSemanine: (total: Int, effectuees: Int, duree: Int) {
        let total = seancesSemaine.count
        let effectuees = seancesSemaine.filter { $0.statut == .effectue }.count
        let duree = seancesSemaine.reduce(0) { $0 + $1.dureeMinutes }
        return (total, effectuees, duree)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Sélecteur de semaine
                Picker("Semaine", selection: $selectedWeek) {
                    ForEach(0..<3) { index in
                        Text(weeks[index].0).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top)
                
                // MARK: - Stats rapides
                if !seancesSemaine.isEmpty {
                    HStack(spacing: 20) {
                        StatBadge(
                            value: "\(statsSemanine.effectuees)/\(statsSemanine.total)",
                            label: "séances",
                            color: .blue
                        )
                        StatBadge(
                            value: formatDuree(statsSemanine.duree),
                            label: "total",
                            color: .orange
                        )
                    }
                    .padding(.vertical, 8)
                }
                
                // MARK: - Liste des séances
                if seancesParJour.isEmpty {
                    ContentUnavailableView {
                        Label("Aucune séance", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("Demande à ton coach IA de générer un plan d'entraînement !")
                    } actions: {
                        Button("Générer un plan") {
                            // TODO: Naviguer vers le chat avec une requête
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(seancesParJour, id: \.0) { jour, seancesDuJour in
                            Section(jour) {
                                ForEach(seancesDuJour) { seance in
                                    SeanceCard(seance: seance)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedSeance = seance
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                modelContext.delete(seance)
                                            } label: {
                                                Label("Supprimer", systemImage: "trash")
                                            }
                                            
                                            Button {
                                                selectedSeance = seance
                                            } label: {
                                                Label("Modifier", systemImage: "pencil")
                                            }
                                            .tint(.blue)
                                        }
                                        .swipeActions(edge: .leading) {
                                            Button {
                                                toggleStatut(seance)
                                            } label: {
                                                if seance.statut == .effectue {
                                                    Label("Non fait", systemImage: "xmark")
                                                } else {
                                                    Label("Fait !", systemImage: "checkmark")
                                                }
                                            }
                                            .tint(seance.statut == .effectue ? .orange : .green)
                                        }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Planning")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(role: .destructive) {
                            deleteAllIASeances()
                        } label: {
                            Label("Supprimer toutes les séances IA", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSeance = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSeance) {
                AddSeanceView()
            }
            .sheet(item: $selectedSeance) { seance in
                SeanceDetailView(seance: seance)
            }
        }
    }
    
    private func toggleStatut(_ seance: Seance) {
        withAnimation {
            if seance.statut == .effectue {
                seance.statut = .planifie
            } else {
                seance.statut = .effectue
            }
        }
    }
    
    // Supprime TOUTES les séances générées par l'IA (planifiées)
    private func deleteAllIASeances() {
        let iaSeances = seances.filter { seance in
            // Critère : source == .ia OU planId != nil (anciennes séances IA)
            let isFromIA = seance.source == .ia || seance.planId != nil
            let isPlanifie = seance.statut == .planifie
            return isFromIA && isPlanifie
        }
        
        print("🗑️ Suppression de \(iaSeances.count) séances IA")
        
        for seance in iaSeances {
            modelContext.delete(seance)
        }
    }
    
    private func formatDuree(_ minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            let m = minutes % 60
            return m > 0 ? "\(h)h\(m)" : "\(h)h"
        }
        return "\(minutes)min"
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Seance Card

struct SeanceCard: View {
    let seance: Seance
    
    var body: some View {
        HStack(spacing: 12) {
            // Indicateur de type avec statut
            VStack(spacing: 4) {
                Text(seance.type.emoji)
                    .font(.title2)
                
                // Indicateur de statut
                Group {
                    switch seance.statut {
                    case .effectue:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .annule:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    case .reporte:
                        Image(systemName: "arrow.uturn.right.circle.fill")
                            .foregroundStyle(.orange)
                    case .planifie:
                        // Badge selon la source
                        switch seance.sourceAffichage {
                        case .ia:
                            Text("IA")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.purple)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        case .strava:
                            Image(systemName: "link.circle.fill")
                                .foregroundStyle(.orange)
                        case .manuel:
                            Image(systemName: "circle")
                                .foregroundStyle(.gray.opacity(0.3))
                        }
                    }
                }
                .font(.caption)
            }
            .frame(width: 40)
            
            // Contenu
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(seance.type.rawValue)
                        .font(.headline)
                        .foregroundStyle(seance.statut == .annule ? .secondary : .primary)
                    
                    Spacer()
                    
                    Text(seance.dureeFormatee)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Text(seance.description_)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Label(seance.sport, systemImage: sportIcon(for: seance.sport))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    // Afficher distance si effectuée
                    if seance.statut == .effectue, let distance = seance.distanceKm, distance > 0 {
                        Text(String(format: "%.1f km", distance))
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    
                    Text(seance.heureFormatee)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(seance.statut == .annule ? 0.5 : 1.0)
    }
    
    private func sportIcon(for sport: String) -> String {
        switch sport.lowercased() {
        case "course", "running": return "figure.run"
        case "vélo", "cycling": return "figure.outdoor.cycle"
        case "natation", "swimming": return "figure.pool.swim"
        case "renforcement", "musculation": return "dumbbell.fill"
        default: return "sportscourt.fill"
        }
    }
}

// MARK: - Add Seance View

struct AddSeanceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var date = Date()
    @State private var type: TypeSeance = .endurance
    @State private var sport = "Course"
    @State private var duree = 45
    @State private var description_ = ""
    @State private var intensite: Intensite = .modere
    
    let sports = ["Course", "Vélo", "Natation", "Renforcement", "Autre"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Quand ?") {
                    DatePicker("Date et heure", selection: $date)
                }
                
                Section("Quoi ?") {
                    Picker("Type", selection: $type) {
                        ForEach(TypeSeance.allCases, id: \.self) { type in
                            Text("\(type.emoji) \(type.rawValue)").tag(type)
                        }
                    }
                    
                    Picker("Sport", selection: $sport) {
                        ForEach(sports, id: \.self) { s in
                            Text(s).tag(s)
                        }
                    }
                    
                    Stepper("Durée: \(duree) min", value: $duree, in: 10...240, step: 5)
                    
                    Picker("Intensité", selection: $intensite) {
                        ForEach(Intensite.allCases, id: \.self) { i in
                            Text(i.rawValue).tag(i)
                        }
                    }
                }
                
                Section("Description") {
                    TextField("Détails de la séance...", text: $description_, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Nouvelle séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        addSeance()
                    }
                    .bold()
                }
            }
        }
    }
    
    private func addSeance() {
        let seance = Seance(
            date: date,
            type: type,
            sport: sport,
            dureeMinutes: duree,
            description: description_.isEmpty ? type.rawValue : description_,
            intensite: intensite
        )
        modelContext.insert(seance)
        dismiss()
    }
}

// MARK: - Seance Detail View

struct SeanceDetailView: View {
    @Bindable var seance: Seance
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(seance.type.emoji)
                            .font(.largeTitle)
                        
                        VStack(alignment: .leading) {
                            HStack {
                                Text(seance.type.rawValue)
                                    .font(.headline)
                                
                                // Badge selon la source
                                switch seance.sourceAffichage {
                                case .ia:
                                    Text("Généré par IA")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                case .strava:
                                    Text("Strava")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.orange)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                case .manuel:
                                    EmptyView()
                                }
                            }
                            Text(seance.dateFormatee)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Détails") {
                    LabeledContent("Sport", value: seance.sport)
                    LabeledContent("Durée", value: seance.dureeFormatee)
                    LabeledContent("Intensité", value: seance.intensite.rawValue)
                    
                    // Picker pour le statut
                    Picker("Statut", selection: $seance.statut) {
                        ForEach([StatutSeance.planifie, .effectue, .annule, .reporte], id: \.self) { statut in
                            Text("\(statut.emoji) \(statut.rawValue)").tag(statut)
                        }
                    }
                }
                
                Section("Description") {
                    Text(seance.description_)
                }
                
                Section("Reprogrammer") {
                    DatePicker("Nouvelle date", selection: $seance.date)
                }
                
                Section("Après la séance") {
                    // Distance
                    HStack {
                        Text("Distance")
                        Spacer()
                        TextField("km", value: Binding(
                            get: { seance.distanceKm ?? 0 },
                            set: { seance.distanceKm = $0 > 0 ? $0 : nil }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        Text("km")
                            .foregroundStyle(.secondary)
                    }
                    
                    // Ressenti
                    Picker("Ressenti", selection: Binding(
                        get: { seance.ressenti ?? 5 },
                        set: { seance.ressenti = $0 }
                    )) {
                        ForEach(1...10, id: \.self) { n in
                            Text("\(n)/10").tag(n)
                        }
                    }
                    
                    // Commentaire
                    TextField("Commentaire", text: Binding(
                        get: { seance.commentaire ?? "" },
                        set: { seance.commentaire = $0.isEmpty ? nil : $0 }
                    ), axis: .vertical)
                }
            }
            .navigationTitle("Détails")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    PlanningView()
        .modelContainer(for: [Athlete.self, Seance.self, ChatMessage.self], inMemory: true)
}
