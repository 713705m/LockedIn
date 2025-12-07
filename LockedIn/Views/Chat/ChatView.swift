import SwiftUI
import SwiftData

// MARK: - Mode de conversation avec l'IA
enum CoachMode: Equatable {
    case accueil                    // Écran d'accueil avec les 3 options
    case creationWizard             // Wizard de création guidée
    case modifierObjectif           // Formulaire modification objectif
    case ajusterPlan                // Chat libre pour ajuster le plan
    case chatEnCours                // Chat actif (après génération ou modification)
    case success(Int)               // Écran de succès avec nombre de séances
}

// MARK: - Étape du wizard de création
enum WizardStep: Int, CaseIterable {
    case objectif = 0
    case allures = 1
    case precisions = 2
    case dateDebut = 3
    
    var titre: String {
        switch self {
        case .objectif: return "Ton objectif"
        case .allures: return "Tes allures"
        case .precisions: return "Précisions"
        case .dateDebut: return "Date de début"
        }
    }
    
    var icone: String {
        switch self {
        case .objectif: return "flag.fill"
        case .allures: return "speedometer"
        case .precisions: return "text.bubble.fill"
        case .dateDebut: return "calendar"
        }
    }
}

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(sort: \ChatMessage.timestamp) private var messages: [ChatMessage]
    @Query private var athletes: [Athlete]
    @Query(sort: \Seance.date) private var seances: [Seance]
    
    @State private var viewModel = ChatViewModel()
    @State private var inputText = ""
    @State private var isLoading = false
    
    // Mode actuel
    @State private var mode: CoachMode = .accueil
    
    // Wizard state
    @State private var wizardStep: WizardStep = .objectif
    @State private var wizardData = WizardData()
    
    // Plan ID pour versioning
    @State private var currentPlanId: String?
    
    private var athlete: Athlete? { athletes.first }
    
    private var hasExistingPlan: Bool {
        seances.contains { $0.sourceAffichage == .ia && $0.statut == .planifie }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                switch mode {
                case .accueil:
                    AccueilCoachView(
                        hasExistingPlan: hasExistingPlan,
                        athlete: athlete,
                        onCreerPlan: { mode = .creationWizard },
                        onModifierObjectif: { mode = .modifierObjectif },
                        onAjusterPlan: { startAjusterPlan() }
                    )
                    
                case .creationWizard:
                    CreationWizardView(
                        step: $wizardStep,
                        data: $wizardData,
                        athlete: athlete,
                        onBack: { handleWizardBack() },
                        onNext: { handleWizardNext() },
                        onGenerate: { generatePlan() }
                    )
                    
                case .modifierObjectif:
                    ModifierObjectifView(
                        athlete: athlete,
                        onSave: { regenererApresModification() },
                        onCancel: { mode = .accueil }
                    )
                    
                case .ajusterPlan, .chatEnCours:
                    ChatConversationView(
                        messages: messages,
                        inputText: $inputText,
                        isLoading: isLoading,
                        onSend: { sendMessage() }
                    )
                    
                case .success(let count):
                    SuccessView(
                        seancesCount: count,
                        onDismiss: { resetToAccueil() }
                    )
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showBackButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            handleGlobalBack()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
        }
        .onAppear {
            // Initialiser wizardData avec les données de l'athlète
            if let athlete = athlete {
                wizardData.prefillFrom(athlete: athlete)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var navigationTitle: String {
        switch mode {
        case .accueil: return "Coach IA 🏃"
        case .creationWizard: return wizardStep.titre
        case .modifierObjectif: return "Mon objectif"
        case .ajusterPlan, .chatEnCours: return "Coach IA 💬"
        case .success: return "C'est fait ! 🎉"
        }
    }
    
    private var showBackButton: Bool {
        switch mode {
        case .accueil, .success: return false
        default: return true
        }
    }
    
    // MARK: - Actions
    
    private func handleGlobalBack() {
        switch mode {
        case .creationWizard:
            if wizardStep == .objectif {
                mode = .accueil
            } else {
                wizardStep = WizardStep(rawValue: wizardStep.rawValue - 1) ?? .objectif
            }
        case .modifierObjectif, .ajusterPlan, .chatEnCours:
            clearChat()
            mode = .accueil
        default:
            mode = .accueil
        }
    }
    
    private func handleWizardBack() {
        if wizardStep == .objectif {
            mode = .accueil
        } else {
            wizardStep = WizardStep(rawValue: wizardStep.rawValue - 1) ?? .objectif
        }
    }
    
    private func handleWizardNext() {
        if wizardStep.rawValue < WizardStep.allCases.count - 1 {
            wizardStep = WizardStep(rawValue: wizardStep.rawValue + 1) ?? .dateDebut
        }
    }
    
    private func startAjusterPlan() {
        currentPlanId = seances.filter { $0.statut == .planifie && $0.sourceAffichage == .ia }.last?.planId ?? UUID().uuidString
        
        let welcomeMsg = ChatMessage(
            contenu: "Je suis prêt à adapter ton plan ! \n\nQue souhaites-tu modifier ?\n• Décaler une séance\n• Alléger ou intensifier la charge\n• Adapter à une contrainte (blessure, fatigue...)\n• Autre chose ?",
            estUtilisateur: false
        )
        modelContext.insert(welcomeMsg)
        mode = .ajusterPlan
    }
    
    private func generatePlan() {
        // Sauvegarder les données du wizard dans le profil athlète
        if let athlete = athlete {
            wizardData.applyTo(athlete: athlete)
        }
        
        // Supprimer anciennes séances IA
        let oldSeances = seances.filter { $0.source == .ia && $0.statut == .planifie }
        for s in oldSeances {
            modelContext.delete(s)
        }
        
        currentPlanId = UUID().uuidString
        
        // Construire le message de génération avec tout le contexte
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM yyyy"
        let dateString = formatter.string(from: wizardData.dateDebut)
        
        var prompt = "Génère-moi un plan d'entraînement complet. Je souhaite commencer le \(dateString)."
        
        if !wizardData.precisions.isEmpty {
            prompt += " Informations supplémentaires : \(wizardData.precisions)"
        }
        
        prompt += " Propose-moi une séance pour CHAQUE jour (soit un entraînement, soit un jour de repos)."
        
        inputText = prompt
        mode = .chatEnCours
        sendMessage()
    }
    
    private func regenererApresModification() {
        mode = .creationWizard
        wizardStep = .dateDebut
        if let athlete = athlete {
            wizardData.prefillFrom(athlete: athlete)
        }
    }
    
    private func resetToAccueil() {
        clearChat()
        wizardStep = .objectif
        wizardData = WizardData()
        if let athlete = athlete {
            wizardData.prefillFrom(athlete: athlete)
        }
        mode = .accueil
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        let userMessage = ChatMessage(contenu: text, estUtilisateur: true)
        modelContext.insert(userMessage)
        
        inputText = ""
        isLoading = true
        
        Task {
            do {
                let isAdjusting = (mode == .ajusterPlan)
                
                let (responseString, newSeances) = try await viewModel.sendMessage(
                    text,
                    history: messages,
                    athlete: athlete,
                    allSeances: seances,
                    wizardData: isAdjusting ? nil : wizardData,
                    isAdjustmentMode: isAdjusting
                )
                
                let aiMessage = ChatMessage(contenu: responseString, estUtilisateur: false)
                modelContext.insert(aiMessage)
                
                if !newSeances.isEmpty {
                    handleNewSeances(newSeances)
                    
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    
                    await MainActor.run {
                        mode = .success(newSeances.count)
                    }
                }
                
            } catch {
                let errorMessage = ChatMessage.messageErreur()
                modelContext.insert(errorMessage)
                print("Erreur API: \(error)")
            }
            
            isLoading = false
        }
    }
    
    private func handleNewSeances(_ seancesIA: [SeanceFromIA]) {
        let planId = currentPlanId ?? UUID().uuidString
        currentPlanId = planId
        
        let seancesToDelete = seances.filter { existingSeance in
            let isFromIA = existingSeance.source == .ia || existingSeance.planId != nil
            let isPlanifie = existingSeance.statut == .planifie
            let isFuture = existingSeance.date >= Calendar.current.startOfDay(for: Date())
            return isFromIA && isPlanifie && isFuture
        }
        
        for s in seancesToDelete {
            modelContext.delete(s)
        }
        
        for seanceIA in seancesIA {
            if let newSeance = seanceIA.toSeance(planId: planId) {
                modelContext.insert(newSeance)
            }
        }
    }
    
    private func clearChat() {
        for message in messages {
            modelContext.delete(message)
        }
        currentPlanId = nil
    }
}

// MARK: - Wizard Data

struct WizardData {
    // Objectif
    var typeObjectif: String = "Marathon"
    var dateObjectif: Date = Date().addingTimeInterval(60*60*24*90)
    var garderObjectif: Bool = true
    
    // Allures
    var allureEndurance: String = ""  // Format "5'30"
    var allureSeuil: String = ""
    var vma: String = ""
    var garderAllures: Bool = true
    
    // Estimation allures (si pas connues)
    var estimationMode: String? = nil  // "temps", "niveau", "inconnu"
    var niveauEstime: String = "intermediaire"  // "debutant", "intermediaire", "confirme", "expert"
    var distanceReference: String = "10 km"
    var tempsHeures: String = ""
    var tempsMinutes: String = ""
    var tempsSecondes: String = ""
    
    // Précisions
    var precisions: String = ""
    
    // Date début
    var dateDebut: Date = Date()
    
    mutating func prefillFrom(athlete: Athlete) {
        typeObjectif = athlete.typeObjectif
        dateObjectif = athlete.dateObjectif
        
        if let allure = athlete.allureEndurance {
            allureEndurance = Athlete.formatAllure(allure)
        }
        if let allure = athlete.allureSeuil {
            allureSeuil = Athlete.formatAllure(allure)
        }
        if let v = athlete.vma {
            vma = String(format: "%.1f", v)
        }
        if let blessures = athlete.blessures, !blessures.isEmpty {
            precisions = blessures
        }
    }
    
    func applyTo(athlete: Athlete) {
        if !garderObjectif {
            athlete.typeObjectif = typeObjectif
            athlete.dateObjectif = dateObjectif
        }
        
        if !garderAllures {
            if let allure = Athlete.parseAllure(allureEndurance) {
                athlete.allureEndurance = allure
            }
            if let allure = Athlete.parseAllure(allureSeuil) {
                athlete.allureSeuil = allure
            }
            if let v = Double(vma.replacingOccurrences(of: ",", with: ".")) {
                athlete.vma = v
            }
        }
        
        if !precisions.isEmpty {
            athlete.blessures = precisions
        }
    }
}

// MARK: - Accueil Coach View

struct AccueilCoachView: View {
    let hasExistingPlan: Bool
    let athlete: Athlete?
    let onCreerPlan: () -> Void
    let onModifierObjectif: () -> Void
    let onAjusterPlan: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(.blue)
                    
                    Text("Ton Coach IA")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    if let athlete = athlete, athlete.onboardingComplete {
                        Text("Objectif : \(athlete.typeObjectif) dans \(athlete.semainesRestantes) semaines")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 40)
                
                // Options
                VStack(spacing: 16) {
                    // Option 1 : Créer un plan
                    OptionCard(
                        icon: "sparkles",
                        iconColor: .blue,
                        title: hasExistingPlan ? "Recréer un plan" : "Créer mon plan",
                        subtitle: "Génère un programme personnalisé étape par étape",
                        action: onCreerPlan
                    )
                    
                    // Option 2 : Modifier objectif
                    OptionCard(
                        icon: "flag.fill",
                        iconColor: .orange,
                        title: "Modifier mon objectif",
                        subtitle: "Changer la date, le type de course ou mes allures",
                        action: onModifierObjectif
                    )
                    
                    // Option 3 : Ajuster le plan (si plan existe)
                    if hasExistingPlan {
                        OptionCard(
                            icon: "pencil.and.outline",
                            iconColor: .green,
                            title: "Ajuster mon plan",
                            subtitle: "Décaler une séance, alléger la charge...",
                            action: onAjusterPlan
                        )
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 40)
            }
        }
    }
}

struct OptionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .frame(width: 44, height: 44)
                    .background(iconColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Creation Wizard View

struct CreationWizardView: View {
    @Binding var step: WizardStep
    @Binding var data: WizardData
    let athlete: Athlete?
    let onBack: () -> Void
    let onNext: () -> Void
    let onGenerate: () -> Void
    
    private var hasExistingObjectif: Bool {
        athlete?.onboardingComplete == true
    }
    
    private var hasExistingAllures: Bool {
        athlete?.allureEndurance != nil || athlete?.vma != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            ProgressBar(currentStep: step.rawValue, totalSteps: WizardStep.allCases.count)
                .padding(.horizontal)
                .padding(.top, 8)
            
            ScrollView {
                VStack(spacing: 24) {
                    switch step {
                    case .objectif:
                        ObjectifStepView(
                            data: $data,
                            hasExisting: hasExistingObjectif,
                            existingType: athlete?.typeObjectif ?? "",
                            existingDate: athlete?.dateObjectif ?? Date()
                        )
                        
                    case .allures:
                        AlluresStepView(
                            data: $data,
                            hasExisting: hasExistingAllures,
                            athlete: athlete
                        )
                        
                    case .precisions:
                        PrecisionsStepView(data: $data)
                        
                    case .dateDebut:
                        DateDebutStepView(data: $data)
                    }
                }
                .padding()
            }
            
            // Navigation buttons
            HStack(spacing: 16) {
                if step != .objectif {
                    Button {
                        onBack()
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
                    if step == .dateDebut {
                        onGenerate()
                    } else {
                        onNext()
                    }
                } label: {
                    Text(step == .dateDebut ? "Générer mon plan ✨" : "Suivant")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
    }
}

struct ProgressBar: View {
    let currentStep: Int
    let totalSteps: Int
    
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= currentStep ? Color.blue : Color(.systemGray4))
                    .frame(height: 4)
            }
        }
    }
}

// MARK: - Wizard Steps

struct ObjectifStepView: View {
    @Binding var data: WizardData
    let hasExisting: Bool
    let existingType: String
    let existingDate: Date
    
    let typesObjectifs = ["Marathon", "Semi-Marathon", "10K", "Trail", "Triathlon", "Autre"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("🎯 Quel est ton objectif ?")
                .font(.title2)
                .fontWeight(.bold)
            
            if hasExisting {
                // Toggle pour garder ou modifier
                Toggle(isOn: $data.garderObjectif) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Garder mon objectif actuel")
                            .font(.headline)
                        Text("\(existingType) - \(existingDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            if !hasExisting || !data.garderObjectif {
                VStack(spacing: 16) {
                    Picker("Type d'objectif", selection: $data.typeObjectif) {
                        ForEach(typesObjectifs, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    
                    DatePicker(
                        "Date de l'objectif",
                        selection: $data.dateObjectif,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact)
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

struct AlluresStepView: View {
    @Binding var data: WizardData
    let hasExisting: Bool
    let athlete: Athlete?
    
    @State private var modeAllure: ModeAllure = .connait
    
    enum ModeAllure: String, CaseIterable {
        case connait = "Je connais mes allures"
        case tempsRecent = "J'ai un temps de course récent"
        case niveau = "Je choisis mon niveau"
        case inconnu = "Je ne sais pas"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("⏱️ Tes allures de référence")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Ces informations aident l'IA à personnaliser tes séances.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if hasExisting {
                Toggle(isOn: $data.garderAllures) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Garder mes allures actuelles")
                            .font(.headline)
                        if let athlete = athlete {
                            Text("Endurance: \(Athlete.formatAllure(athlete.allureEndurance)) • VMA: \(athlete.vma.map { String(format: "%.1f km/h", $0) } ?? "--")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            if !hasExisting || !data.garderAllures {
                // Sélection du mode
                VStack(alignment: .leading, spacing: 12) {
                    Text("Comment veux-tu renseigner tes allures ?")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    ForEach(ModeAllure.allCases, id: \.self) { mode in
                        ModeAllureButton(
                            mode: mode,
                            isSelected: modeAllure == mode,
                            action: {
                                modeAllure = mode
                                updateDataForMode(mode)
                            }
                        )
                    }
                }
                
                // Contenu selon le mode
                switch modeAllure {
                case .connait:
                    VStack(spacing: 16) {
                        AllureField(label: "Allure endurance", placeholder: "ex: 5'45", value: $data.allureEndurance, hint: "min/km")
                        AllureField(label: "Allure seuil", placeholder: "ex: 4'50", value: $data.allureSeuil, hint: "min/km")
                        
                        HStack {
                            Text("VMA")
                                .frame(width: 120, alignment: .leading)
                            TextField("ex: 16.5", text: $data.vma)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                            Text("km/h")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                case .tempsRecent:
                    TempsRecentView(data: $data)
                    
                case .niveau:
                    NiveauView(data: $data)
                    
                case .inconnu:
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        
                        Text("Pas de souci !")
                            .font(.headline)
                        
                        Text("L'IA te proposera des allures progressives adaptées aux débutants/intermédiaires. Tu pourras ajuster après tes premières séances.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
    
    private func updateDataForMode(_ mode: ModeAllure) {
        switch mode {
        case .inconnu:
            data.niveauEstime = "intermediaire"
            data.estimationMode = "inconnu"
        case .niveau:
            data.estimationMode = "niveau"
        case .tempsRecent:
            data.estimationMode = "temps"
        case .connait:
            data.estimationMode = nil
        }
    }
}

struct ModeAllureButton: View {
    let mode: AlluresStepView.ModeAllure
    let isSelected: Bool
    let action: () -> Void
    
    var icon: String {
        switch mode {
        case .connait: return "speedometer"
        case .tempsRecent: return "stopwatch"
        case .niveau: return "figure.run"
        case .inconnu: return "questionmark.circle"
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                Text(mode.rawValue)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TempsRecentView: View {
    @Binding var data: WizardData
    
    let distances = ["5 km", "10 km", "Semi-marathon", "Marathon"]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Entre un temps récent sur une distance")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Picker("Distance", selection: $data.distanceReference) {
                ForEach(distances, id: \.self) { d in
                    Text(d).tag(d)
                }
            }
            .pickerStyle(.segmented)
            
            HStack(spacing: 8) {
                Text("Temps :")
                
                TextField("HH", text: $data.tempsHeures)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                Text("h")
                
                TextField("MM", text: $data.tempsMinutes)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                Text("min")
                
                TextField("SS", text: $data.tempsSecondes)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 50)
                Text("sec")
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            if let vmaEstimee = estimerVMA() {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.orange)
                    Text("VMA estimée : **\(String(format: "%.1f", vmaEstimee)) km/h**")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    private func estimerVMA() -> Double? {
        let h = Double(data.tempsHeures) ?? 0
        let m = Double(data.tempsMinutes) ?? 0
        let s = Double(data.tempsSecondes) ?? 0
        
        let totalMinutes = h * 60 + m + s / 60
        guard totalMinutes > 0 else { return nil }
        
        let distanceKm: Double
        switch data.distanceReference {
        case "5 km": distanceKm = 5
        case "10 km": distanceKm = 10
        case "Semi-marathon": distanceKm = 21.1
        case "Marathon": distanceKm = 42.195
        default: return nil
        }
        
        // Vitesse moyenne
        let vitesseMoyenne = distanceKm / (totalMinutes / 60)
        
        // Estimation VMA basée sur %VMA typique pour chaque distance
        // 5km ~93%, 10km ~90%, Semi ~85%, Marathon ~80%
        let pourcentageVMA: Double
        switch data.distanceReference {
        case "5 km": pourcentageVMA = 0.93
        case "10 km": pourcentageVMA = 0.90
        case "Semi-marathon": pourcentageVMA = 0.85
        case "Marathon": pourcentageVMA = 0.80
        default: pourcentageVMA = 0.85
        }
        
        let vmaEstimee = vitesseMoyenne / pourcentageVMA
        
        // Mettre à jour les données
        data.vma = String(format: "%.1f", vmaEstimee)
        
        return vmaEstimee
    }
}

struct NiveauView: View {
    @Binding var data: WizardData
    
    let niveaux: [(id: String, titre: String, description: String, vma: String)] = [
        ("debutant", "Débutant", "Je cours depuis moins d'1 an, < 3x/sem", "12-14"),
        ("intermediaire", "Intermédiaire", "Je cours régulièrement depuis 1-3 ans", "14-16"),
        ("confirme", "Confirmé", "Je cours depuis +3 ans, compétitions régulières", "16-18"),
        ("expert", "Expert", "Compétiteur assidu, gros volume", "18-20+")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choisis ton niveau")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            ForEach(niveaux, id: \.id) { niveau in
                Button {
                    data.niveauEstime = niveau.id
                    // Estimer une VMA moyenne pour ce niveau
                    switch niveau.id {
                    case "debutant": data.vma = "13"
                    case "intermediaire": data.vma = "15"
                    case "confirme": data.vma = "17"
                    case "expert": data.vma = "19"
                    default: break
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(niveau.titre)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(niveau.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("VMA")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(niveau.vma)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                        }
                        if data.niveauEstime == niveau.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                    .padding()
                    .background(data.niveauEstime == niveau.id ? Color.blue.opacity(0.1) : Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(data.niveauEstime == niveau.id ? Color.blue : Color.clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AllureField: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    let hint: String
    
    var body: some View {
        HStack {
            Text(label)
                .frame(width: 120, alignment: .leading)
            TextField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)
            Text(hint)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct PrecisionsStepView: View {
    @Binding var data: WizardData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("📝 Des précisions ?")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Partage tout ce qui peut aider l'IA à personnaliser ton plan.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            TextEditor(text: $data.precisions)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Suggestions
            VStack(alignment: .leading, spacing: 12) {
                Text("Exemples :")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                SuggestionChip(text: "Douleur au genou droit", target: $data.precisions)
                SuggestionChip(text: "Disponible surtout le week-end", target: $data.precisions)
                SuggestionChip(text: "Je veux progresser en VMA", target: $data.precisions)
                SuggestionChip(text: "Fatigue accumulée ces derniers jours", target: $data.precisions)
            }
        }
    }
}

struct SuggestionChip: View {
    let text: String
    @Binding var target: String
    
    var body: some View {
        Button {
            if target.isEmpty {
                target = text
            } else {
                target += ". " + text
            }
        } label: {
            Text("+ \(text)")
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundStyle(.blue)
                .clipShape(Capsule())
        }
    }
}

struct DateDebutStepView: View {
    @Binding var data: WizardData
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("📅 Quand commencer ?")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Choisis la date de début de ton plan. L'IA va générer 2 semaines de séances.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            DatePicker(
                "Date de début",
                selection: $data.dateDebut,
                in: Date()...,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Modifier Objectif View

struct ModifierObjectifView: View {
    let athlete: Athlete?
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @State private var typeObjectif: String = "Marathon"
    @State private var dateObjectif: Date = Date().addingTimeInterval(60*60*24*90)
    @State private var allureEndurance: String = ""
    @State private var allureSeuil: String = ""
    @State private var vma: String = ""
    
    let typesObjectifs = ["Marathon", "Semi-Marathon", "10K", "Trail", "Triathlon", "Autre"]
    
    var body: some View {
        Form {
            Section("Objectif") {
                Picker("Type", selection: $typeObjectif) {
                    ForEach(typesObjectifs, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                
                DatePicker("Date", selection: $dateObjectif, in: Date()..., displayedComponents: .date)
            }
            
            Section("Allures (optionnel)") {
                HStack {
                    Text("Endurance")
                    Spacer()
                    TextField("5'30", text: $allureEndurance)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("/km")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Seuil")
                    Spacer()
                    TextField("4'45", text: $allureSeuil)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("/km")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("VMA")
                    Spacer()
                    TextField("16.5", text: $vma)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("km/h")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                Button("Enregistrer et adapter mon plan") {
                    saveChanges()
                    onSave()
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.blue)
                
                Button("Annuler", role: .cancel) {
                    onCancel()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            if let athlete = athlete {
                typeObjectif = athlete.typeObjectif
                dateObjectif = athlete.dateObjectif
                if let a = athlete.allureEndurance { allureEndurance = Athlete.formatAllure(a) }
                if let a = athlete.allureSeuil { allureSeuil = Athlete.formatAllure(a) }
                if let v = athlete.vma { vma = String(format: "%.1f", v) }
            }
        }
    }
    
    private func saveChanges() {
        guard let athlete = athlete else { return }
        
        athlete.typeObjectif = typeObjectif
        athlete.dateObjectif = dateObjectif
        
        if let allure = Athlete.parseAllure(allureEndurance) {
            athlete.allureEndurance = allure
        }
        if let allure = Athlete.parseAllure(allureSeuil) {
            athlete.allureSeuil = allure
        }
        if let v = Double(vma.replacingOccurrences(of: ",", with: ".")) {
            athlete.vma = v
        }
    }
}

// MARK: - Chat Conversation View

struct ChatConversationView: View {
    let messages: [ChatMessage]
    @Binding var inputText: String
    let isLoading: Bool
    let onSend: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if isLoading {
                            LoadingBubble()
                                .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: isLoading) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
            }
            
            Divider()
            
            // Input Bar
            HStack(spacing: 12) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                
                Button {
                    onSend()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(inputText.isEmpty ? .gray : .blue)
                }
                .disabled(inputText.isEmpty || isLoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if isLoading {
                proxy.scrollTo("loading", anchor: .bottom)
            } else if let lastMessage = messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Sous-vues existantes (conservées)

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.estUtilisateur { Spacer(minLength: 60) }
            
            VStack(alignment: message.estUtilisateur ? .trailing : .leading, spacing: 4) {
                Text(message.contenu)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.estUtilisateur ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(message.estUtilisateur ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                
                Text(message.heureFormatee)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            if !message.estUtilisateur { Spacer(minLength: 60) }
        }
    }
}

struct LoadingBubble: View {
    @State private var animating = false
    
    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray5))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            
            Spacer()
        }
        .onAppear { animating = true }
    }
}

struct SuccessView: View {
    let seancesCount: Int
    let onDismiss: () -> Void
    
    @State private var showCheckmark = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                    .scaleEffect(showCheckmark ? 1 : 0.5)
                    .opacity(showCheckmark ? 1 : 0)
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    showCheckmark = true
                }
            }
            
            VStack(spacing: 12) {
                Text("Plan créé ! 🎉")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("\(seancesCount) séances ont été ajoutées à ton planning")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            Button {
                onDismiss()
            } label: {
                Text("Voir mon planning")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

#Preview {
    ChatView()
        .modelContainer(for: [Athlete.self, Seance.self, ChatMessage.self], inMemory: true)
}
