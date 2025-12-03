import SwiftUI
import SwiftData

struct PlanningView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Seance.date) private var seances: [Seance]
    
    @State private var selectedWeek = 0
    @State private var showingAddSeance = false
    @State private var selectedSeance: Seance?
    
    // Dates des 3 prochaines semaines
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
            
            let label = weekOffset == 0 ? "Cette semaine" :
                        weekOffset == 1 ? "Semaine prochaine" :
                        "Dans 2 semaines"
            
            return (label, actualStart, weekEnd)
        }
    }
    
    // Séances filtrées pour la semaine sélectionnée
    private var seancesSemaine: [Seance] {
        guard selectedWeek < weeks.count else { return [] }
        let (_, start, end) = weeks[selectedWeek]
        
        return seances.filter { seance in
            seance.date >= start && seance.date <= end
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
                .padding()
                
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
}

// MARK: - Seance Card

struct SeanceCard: View {
    let seance: Seance
    
    var body: some View {
        HStack(spacing: 12) {
            // Indicateur de type
            VStack {
                Text(seance.type.emoji)
                    .font(.title2)
                
                if seance.statut == .effectue {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            .frame(width: 40)
            
            // Contenu
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(seance.type.rawValue)
                        .font(.headline)
                    
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
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(seance.type.emoji)
                            .font(.largeTitle)
                        
                        VStack(alignment: .leading) {
                            Text(seance.type.rawValue)
                                .font(.headline)
                            Text(seance.dateFormatee)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Détails") {
                    LabeledContent("Sport", value: seance.sport)
                    LabeledContent("Durée", value: seance.dureeFormatee)
                    LabeledContent("Intensité", value: seance.intensite.rawValue)
                    LabeledContent("Statut", value: "\(seance.statut.emoji) \(seance.statut.rawValue)")
                }
                
                Section("Description") {
                    Text(seance.description_)
                }
                
                Section("Reprogrammer") {
                    DatePicker("Nouvelle date", selection: $seance.date)
                }
                
                Section("Après la séance") {
                    Picker("Ressenti", selection: Binding(
                        get: { seance.ressenti ?? 5 },
                        set: { seance.ressenti = $0 }
                    )) {
                        ForEach(1...10, id: \.self) { n in
                            Text("\(n)/10").tag(n)
                        }
                    }
                    
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
