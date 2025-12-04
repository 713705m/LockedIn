import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    
    // On récupère les messages
    @Query(sort: \ChatMessage.timestamp) private var messages: [ChatMessage]
    // On récupère les athlètes
    @Query private var athletes: [Athlete]
    // On récupère toutes les séances pour les envoyer au contexte de l'IA
    @Query(sort: \Seance.date) private var seances: [Seance]
    
    @State private var viewModel = ChatViewModel()
    @State private var inputText = ""
    @State private var isLoading = false
    
    // Pour gérer le versioning du plan
    @State private var currentPlanId: String?
    
    // Pour le choix de la date de début
    @State private var showDatePicker = false
    @State private var selectedStartDate = Date()
    
    // Pour afficher le message de succès
    @State private var showSuccessMessage = false
    @State private var seancesCreees = 0
    
    private var athlete: Athlete? { athletes.first }
    
    // Vérifie si on a des séances IA planifiées
    private var hasExistingPlan: Bool {
        seances.contains { $0.sourceAffichage == .ia && $0.statut == .planifie }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // MARK: - Accueil avec les 2 boutons OU Chat
                if messages.isEmpty && !showSuccessMessage {
                    // Écran d'accueil avec les boutons
                    AccueilChatView(
                        hasExistingPlan: hasExistingPlan,
                        onNewPlan: {
                            showDatePicker = true
                        },
                        onModifyPlan: {
                            modifyCurrentPlan()
                        }
                    )
                    
                } else if showSuccessMessage {
                    // Message de succès après création
                    SuccessView(
                        seancesCount: seancesCreees,
                        onDismiss: {
                            // Réinitialiser et revenir à l'accueil
                            clearChat()
                            showSuccessMessage = false
                        }
                    )
                    
                } else {
                    // Chat classique
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
                    
                    // MARK: - Input Bar
                    HStack(spacing: 12) {
                        TextField("Message...", text: $inputText, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(1...5)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        
                        Button {
                            sendMessage()
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
            .navigationTitle("Coach IA 🏃")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Bouton retour si on est dans le chat
                if !messages.isEmpty && !showSuccessMessage {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            clearChat()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
            // MARK: - Sheet pour choisir la date de début
            .sheet(isPresented: $showDatePicker) {
                StartDatePickerView(
                    selectedDate: $selectedStartDate,
                    onConfirm: {
                        showDatePicker = false
                        startNewPlan(from: selectedStartDate)
                    },
                    onCancel: {
                        showDatePicker = false
                    }
                )
                .presentationDetents([.medium])
            }
        }
    }
    
    // MARK: - Logique Métier
    
    // Option 1 : L'utilisateur veut un tout nouveau plan
    private func startNewPlan(from startDate: Date) {
        // Supprimer TOUTES les anciennes séances IA planifiées
        // On considère comme "IA" : source == .ia OU planId != nil (anciennes séances)
        let oldSeances = seances.filter { seance in
            let isFromIA = seance.source == .ia || seance.planId != nil
            let isPlanifie = seance.statut == .planifie
            return isFromIA && isPlanifie
        }
        
        print("🗑️ Suppression de \(oldSeances.count) anciennes séances IA")
        for s in oldSeances {
            modelContext.delete(s)
        }
        
        // On génère un nouvel ID unique pour ce cycle
        currentPlanId = UUID().uuidString
        
        // Formatter la date pour le message
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM yyyy"
        let dateString = formatter.string(from: startDate)
        
        // On pré-remplit le message avec la date de début
        inputText = "Génère-moi un plan d'entraînement complet pour mon objectif. Je souhaite commencer le \(dateString). Propose-moi une séance pour CHAQUE jour (soit un entraînement, soit un jour de repos actif ou complet)."
        sendMessage()
    }
    
    // Option 2 : L'utilisateur veut modifier l'existant
    private func modifyCurrentPlan() {
        // On essaie de retrouver l'ID du plan en cours via la dernière séance planifiée
        if let lastSeance = seances.filter({ $0.statut == .planifie && $0.sourceAffichage == .ia }).last {
            currentPlanId = lastSeance.planId ?? UUID().uuidString
        } else {
            currentPlanId = UUID().uuidString
        }
        
        // On insère juste un message de l'IA pour inviter à parler
        let welcomeMsg = ChatMessage(
            contenu: "Je suis prêt à adapter ton plan ! 💪\n\nQue souhaites-tu modifier ?\n• Changer les jours d'entraînement\n• Ajuster l'intensité\n• Modifier la durée des séances\n• Autre chose ?",
            estUtilisateur: false
        )
        modelContext.insert(welcomeMsg)
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // 1. Sauvegarde message utilisateur
        let userMessage = ChatMessage(contenu: text, estUtilisateur: true)
        modelContext.insert(userMessage)
        
        inputText = ""
        isLoading = true
        
        Task {
            do {
                // 2. Appel API avec le contexte complet
                let (responseString, newSeances) = try await viewModel.sendMessage(
                    text,
                    history: messages,
                    athlete: athlete,
                    allSeances: seances
                )
                
                // 3. Sauvegarde réponse IA
                let aiMessage = ChatMessage(contenu: responseString, estUtilisateur: false)
                modelContext.insert(aiMessage)
                
                // 4. Gestion intelligente des séances (Versioning)
                if !newSeances.isEmpty {
                    handleNewSeances(newSeances)
                    
                    // Afficher le message de succès et fermer le chat
                    seancesCreees = newSeances.count
                    
                    // Petit délai pour que l'utilisateur voie la réponse
                    try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 secondes
                    
                    await MainActor.run {
                        showSuccessMessage = true
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
    
    // 🔥 C'est ici que se fait le remplacement des séances
    private func handleNewSeances(_ seancesIA: [SeanceFromIA]) {
        // S'assurer qu'on a un ID de plan
        let planId = currentPlanId ?? UUID().uuidString
        currentPlanId = planId
        
        // 1. Identifier les séances À SUPPRIMER
        // On supprime TOUTES les séances IA planifiées (pas effectuées) dans le futur
        // Critère : source == .ia OU planId != nil (pour les anciennes séances)
        let seancesToDelete = seances.filter { existingSeance in
            let isFromIA = existingSeance.source == .ia || existingSeance.planId != nil
            let isPlanifie = existingSeance.statut == .planifie
            let isFuture = existingSeance.date >= Calendar.current.startOfDay(for: Date())
            return isFromIA && isPlanifie && isFuture
        }
        
        print("🗑️ Suppression de \(seancesToDelete.count) anciennes séances IA planifiées")
        
        // Suppression
        for s in seancesToDelete {
            modelContext.delete(s)
        }
        
        // 2. Ajouter les NOUVELLES séances
        for seanceIA in seancesIA {
            if let newSeance = seanceIA.toSeance(planId: planId) {
                modelContext.insert(newSeance)
            }
        }
        
        print("✅ Plan mis à jour (ID: \(planId)) : \(seancesToDelete.count) supprimées, \(seancesIA.count) ajoutées.")
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
    
    private func clearChat() {
        for message in messages {
            modelContext.delete(message)
        }
        currentPlanId = nil
    }
}

// MARK: - Accueil Chat View

struct AccueilChatView: View {
    let hasExistingPlan: Bool
    let onNewPlan: () -> Void
    let onModifyPlan: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icône
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue)
            
            // Titre
            VStack(spacing: 8) {
                Text("Ton Coach IA")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Prêt à créer ton programme d'entraînement personnalisé")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            // Boutons
            VStack(spacing: 16) {
                // Bouton principal : Nouveau plan
                Button {
                    onNewPlan()
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text(hasExistingPlan ? "Régénérer un nouveau plan" : "Générer mon plan")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                // Bouton secondaire : Modifier (seulement si un plan existe)
                if hasExistingPlan {
                    Button {
                        onModifyPlan()
                    } label: {
                        HStack {
                            Image(systemName: "pencil.and.outline")
                            Text("Modifier mon plan actuel")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Success View

struct SuccessView: View {
    let seancesCount: Int
    let onDismiss: () -> Void
    
    @State private var showCheckmark = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Animation checkmark
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
            
            // Message
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
            
            // Bouton
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

// MARK: - Date Picker View

struct StartDatePickerView: View {
    @Binding var selectedDate: Date
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("📅 Quand veux-tu commencer ?")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Choisis la date de début de ton plan d'entraînement")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                DatePicker(
                    "Date de début",
                    selection: $selectedDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top, 24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commencer") {
                        onConfirm()
                    }
                    .bold()
                }
            }
        }
    }
}

// MARK: - Message Bubble

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

// MARK: - Loading Bubble

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

#Preview {
    ChatView()
        .modelContainer(for: [Athlete.self, Seance.self, ChatMessage.self], inMemory: true)
}
