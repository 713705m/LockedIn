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

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var athletes: [Athlete]
    
    @State private var currentStep = 0
    
    // Step 1: Nom
    @State private var nom = ""
    
    // Step 2: Objectif
    @State private var typeObjectif = "Marathon"
    @State private var dateObjectif = Date().addingTimeInterval(60*60*24*90)
    
    // Step 3: VMA
    @State private var vmaMode: VMAInputMode = .skip
    @State private var vmaDirecte = ""
    @State private var distanceReference = "10 km"
    @State private var tempsHeures = ""
    @State private var tempsMinutes = ""
    @State private var tempsSecondes = ""
    @State private var niveauChoisi = "intermediaire"
    
    enum VMAInputMode: String, CaseIterable {
        case direct = "Je connais ma VMA"
        case fromTime = "J'ai un temps de course"
        case fromLevel = "J'estime mon niveau"
        case skip = "Je ne sais pas encore"
    }
    
    let typesObjectifs = ["Marathon", "Semi-Marathon", "10 km", "5 km", "Trail", "Triathlon", "Autre"]
    let distances = ["5 km", "10 km", "Semi-marathon", "Marathon"]
    let niveaux: [(id: String, titre: String, vma: Double)] = [
        ("debutant", "Débutant (< 1 an de course)", 13),
        ("intermediaire", "Intermédiaire (1-3 ans)", 15),
        ("confirme", "Confirmé (3+ ans)", 17),
        ("expert", "Expert (compétiteur)", 19)
    ]
    
    var vmaCalculee: Double? {
        let h = Double(tempsHeures) ?? 0
        let m = Double(tempsMinutes) ?? 0
        let s = Double(tempsSecondes) ?? 0
        
        let totalMinutes = h * 60 + m + s / 60
        guard totalMinutes > 0 else { return nil }
        
        let distanceKm: Double
        switch distanceReference {
        case "5 km": distanceKm = 5
        case "10 km": distanceKm = 10
        case "Semi-marathon": distanceKm = 21.1
        case "Marathon": distanceKm = 42.195
        default: return nil
        }
        
        let vitesseMoyenne = distanceKm / (totalMinutes / 60)
        
        let pourcentageVMA: Double
        switch distanceReference {
        case "5 km": pourcentageVMA = 0.93
        case "10 km": pourcentageVMA = 0.90
        case "Semi-marathon": pourcentageVMA = 0.85
        case "Marathon": pourcentageVMA = 0.80
        default: pourcentageVMA = 0.85
        }
        
        return vitesseMoyenne / pourcentageVMA
    }
    
    var canProceed: Bool {
        switch currentStep {
        case 0: return !nom.isEmpty
        case 1: return true
        case 2: return true
        default: return true
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                ProgressView(value: Double(currentStep + 1), total: 3)
                    .tint(.blue)
                    .padding(.horizontal)
                    .padding(.top)
                
                // Content
                TabView(selection: $currentStep) {
                    // Step 1: Nom
                    step1View.tag(0)
                    
                    // Step 2: Objectif
                    step2View.tag(1)
                    
                    // Step 3: VMA
                    step3View.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentStep)
                
                // Navigation buttons
                HStack(spacing: 16) {
                    if currentStep > 0 {
                        Button {
                            currentStep -= 1
                        } label: {
                            Text("Retour")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray5))
                                .foregroundStyle(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    Button {
                        if currentStep < 2 {
                            currentStep += 1
                        } else {
                            saveAndDismiss()
                        }
                    } label: {
                        Text(currentStep == 2 ? "Commencer 🚀" : "Suivant")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(canProceed ? Color.blue : Color.gray)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canProceed)
                }
                .padding()
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.large)
        }
        .interactiveDismissDisabled()
    }
    
    private var stepTitle: String {
        switch currentStep {
        case 0: return "Bienvenue ! 👋"
        case 1: return "Ton objectif 🎯"
        case 2: return "Ton niveau ⏱️"
        default: return ""
        }
    }
    
    // MARK: - Step Views
    
    private var step1View: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            Text("Comment tu t'appelles ?")
                .font(.title2)
                .fontWeight(.bold)
            
            TextField("Ton prénom", text: $nom)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
        }
        .padding()
    }
    
    private var step2View: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("Quel est ton prochain objectif ?")
                .font(.title2)
                .fontWeight(.bold)
            
            Picker("Type d'objectif", selection: $typeObjectif) {
                ForEach(typesObjectifs, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .pickerStyle(.wheel)
            .frame(height: 150)
            
            Divider()
                .padding(.horizontal, 40)
            
            VStack(spacing: 8) {
                Text("Date de l'objectif")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                DatePicker(
                    "",
                    selection: $dateObjectif,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .labelsHidden()
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var step3View: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Connais-tu ta VMA ?")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Ça nous aide à personnaliser tes allures d'entraînement")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                // Mode selection
                ForEach(VMAInputMode.allCases, id: \.self) { mode in
                    Button {
                        vmaMode = mode
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                                .foregroundStyle(.primary)
                            Spacer()
                            if vmaMode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding()
                        .background(vmaMode == mode ? Color.blue.opacity(0.1) : Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(vmaMode == mode ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // Input selon le mode
                switch vmaMode {
                case .direct:
                    HStack {
                        Text("VMA")
                        Spacer()
                        TextField("16.5", text: $vmaDirecte)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("km/h")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                case .fromTime:
                    VStack(spacing: 12) {
                        Picker("Distance", selection: $distanceReference) {
                            ForEach(distances, id: \.self) { d in
                                Text(d).tag(d)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        HStack {
                            Text("Temps :")
                            Spacer()
                            TextField("H", text: $tempsHeures)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 45)
                            Text("h")
                            TextField("MM", text: $tempsMinutes)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 45)
                            Text("m")
                            TextField("SS", text: $tempsSecondes)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 45)
                            Text("s")
                        }
                        
                        if let vma = vmaCalculee {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.orange)
                                Text("VMA estimée : **\(String(format: "%.1f", vma)) km/h**")
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                case .fromLevel:
                    VStack(spacing: 8) {
                        ForEach(niveaux, id: \.id) { niveau in
                            Button {
                                niveauChoisi = niveau.id
                            } label: {
                                HStack {
                                    Text(niveau.titre)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("~\(Int(niveau.vma)) km/h")
                                        .foregroundStyle(.blue)
                                    if niveauChoisi == niveau.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding()
                                .background(niveauChoisi == niveau.id ? Color.blue.opacity(0.1) : Color(.systemGray6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                case .skip:
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("Pas de souci !")
                            .font(.headline)
                        Text("Tu pourras ajouter ta VMA plus tard dans ton profil, ou l'IA te proposera des allures adaptées.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
    }
    
    private func saveAndDismiss() {
        if let athlete = athletes.first {
            athlete.nom = nom
            athlete.typeObjectif = typeObjectif
            athlete.dateObjectif = dateObjectif
            
            // VMA selon le mode
            switch vmaMode {
            case .direct:
                if let vma = Double(vmaDirecte.replacingOccurrences(of: ",", with: ".")) {
                    athlete.vma = vma
                }
            case .fromTime:
                if let vma = vmaCalculee {
                    athlete.vma = vma
                }
            case .fromLevel:
                if let niveau = niveaux.first(where: { $0.id == niveauChoisi }) {
                    athlete.vma = niveau.vma
                }
            case .skip:
                break // Pas de VMA
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
