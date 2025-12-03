import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var athletes: [Athlete]
    
    @State private var selectedTab = 0
    @State private var showOnboarding = false
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Tab Chat
            ChatView()
                .tabItem {
                    Label("Coach", systemImage: "message.fill")
                }
                .tag(0)
            
            // MARK: - Tab Planning
            PlanningView()
                .tabItem {
                    Label("Planning", systemImage: "calendar")
                }
                .tag(1)
            
            // MARK: - Tab Stats
            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(2)
            
            // MARK: - Tab Profil
            ProfilView()
                .tabItem {
                    Label("Profil", systemImage: "person.fill")
                }
                .tag(3)
        }
        .onAppear {
            setupInitialData()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
        }
    }
    
    private func setupInitialData() {
        // Crée un profil athlète s'il n'existe pas
        if athletes.isEmpty {
            let newAthlete = Athlete()
            modelContext.insert(newAthlete)
            showOnboarding = true
        } else if let athlete = athletes.first, !athlete.onboardingComplete {
            showOnboarding = true
        }
    }
}

// MARK: - Vue Profil simple

struct ProfilView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var athletes: [Athlete]
    
    private var athlete: Athlete? { athletes.first }
    
    var body: some View {
        NavigationStack {
            List {
                if let athlete = athlete {
                    Section("Objectif") {
                        LabeledContent("Type", value: athlete.typeObjectif)
                        LabeledContent("Date", value: athlete.dateObjectif.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("Jours restants", value: "\(athlete.joursRestants)")
                    }
                    
                    Section("Allures") {
                        LabeledContent("Endurance", value: Athlete.formatAllure(athlete.allureEndurance))
                        LabeledContent("Seuil", value: Athlete.formatAllure(athlete.allureSeuil))
                        LabeledContent("VMA", value: Athlete.formatAllure(athlete.allureVMA))
                    }
                    
                    if let vma = athlete.vma {
                        Section("Physiologie") {
                            LabeledContent("VMA", value: String(format: "%.1f km/h", vma))
                            if let fcMax = athlete.fcMax {
                                LabeledContent("FC Max", value: "\(fcMax) bpm")
                            }
                        }
                    }
                    
                    Section("Entraînement") {
                        LabeledContent("Heures/semaine", value: "\(athlete.heuresParSemaine)h")
                        LabeledContent("Sports", value: athlete.sports.joined(separator: ", "))
                    }
                    
                    Section {
                        Button("Modifier mon profil") {
                            // TODO: Ouvrir l'édition du profil
                        }
                        
                        Button("Connecter Strava") {
                            // TODO: OAuth Strava
                        }
                        .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Mon Profil")
        }
    }
}

// MARK: - Onboarding View (simplifié pour l'instant)

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var athletes: [Athlete]
    
    @State private var nom = ""
    @State private var typeObjectif = "Marathon"
    @State private var dateObjectif = Date().addingTimeInterval(60*60*24*90)
    @State private var vma = ""
    @State private var heuresParSemaine = 5
    
    let typesObjectifs = ["Marathon", "Semi-Marathon", "10K", "Trail", "Triathlon", "Autre"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Qui es-tu ?") {
                    TextField("Ton prénom", text: $nom)
                }
                
                Section("Ton objectif") {
                    Picker("Type", selection: $typeObjectif) {
                        ForEach(typesObjectifs, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    
                    DatePicker("Date de l'objectif",
                              selection: $dateObjectif,
                              in: Date()...,
                              displayedComponents: .date)
                }
                
                Section("Ton niveau") {
                    TextField("VMA (km/h)", text: $vma)
                        .keyboardType(.decimalPad)
                    
                    Stepper("Heures/semaine: \(heuresParSemaine)h",
                           value: $heuresParSemaine,
                           in: 1...20)
                }
                
                Section {
                    Text("Tu pourras affiner ces infos en discutant avec ton coach IA ! 💬")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Bienvenue ! 👋")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commencer") {
                        saveAndDismiss()
                    }
                    .bold()
                    .disabled(nom.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled()
    }
    
    private func saveAndDismiss() {
        if let athlete = athletes.first {
            athlete.nom = nom
            athlete.typeObjectif = typeObjectif
            athlete.dateObjectif = dateObjectif
            athlete.heuresParSemaine = heuresParSemaine
            
            if let vmaDouble = Double(vma.replacingOccurrences(of: ",", with: ".")) {
                athlete.vma = vmaDouble
            }
            
            athlete.onboardingComplete = true
        }
        
        dismiss()
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [Athlete.self, Seance.self, ChatMessage.self], inMemory: true)
}
