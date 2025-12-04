import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    
    // On récupère les messages
    @Query(sort: \ChatMessage.timestamp) private var messages: [ChatMessage]
    // On récupère les athlètes
    @Query private var athletes: [Athlete]
    // NOUVEAU : On récupère toutes les séances pour les envoyer au contexte de l'IA
    @Query(sort: \Seance.date) private var seances: [Seance]
    
    @State private var viewModel = ChatViewModel()
    @State private var inputText = ""
    @State private var isLoading = false
    
    // NOUVEAU : Pour gérer le versioning du plan (savoir quel lot de séances remplacer)
    @State private var currentPlanId: String?
    
    private var athlete: Athlete? { athletes.first }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // MARK: - Choix Initial ou Liste des Messages
                if messages.isEmpty {
                    // Si aucune conversation, on affiche les boutons de choix
                    VStack(spacing: 20) {
                        Spacer()
                        
                        Text("Que veux-tu faire ?")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Button {
                            startNewPlan()
                        } label: {
                            Label("Générer un nouveau plan", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Button {
                            modifyCurrentPlan()
                        } label: {
                            Label("Modifier mon plan actuel", systemImage: "slider.horizontal.3")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.15))
                                .foregroundColor(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        
                        Spacer()
                    }
                    .padding()
                    
                } else {
                    // Sinon, on affiche le chat classique
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
            .navigationTitle("Coach IA 🏃")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nouvelle conversation", systemImage: "trash") {
                            clearChat()
                        }
                        Button("Regénérer le plan", systemImage: "arrow.clockwise") {
                            regeneratePlan()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .onAppear {
                // On ne met plus de message de bienvenue automatique ici
                // pour laisser l'utilisateur choisir via les boutons
            }
        }
    }
    
    // MARK: - Logique Métier
    
    // Option 1 : L'utilisateur veut un tout nouveau plan
    private func startNewPlan() {
        // On génère un nouvel ID unique pour ce cycle
        currentPlanId = UUID().uuidString
        
        // On pré-remplit le message pour lancer la machine
        inputText = "Peux-tu me générer un plan d'entraînement pour mon objectif ?"
        sendMessage()
    }
    
    // Option 2 : L'utilisateur veut modifier l'existant
    private func modifyCurrentPlan() {
        // On essaie de retrouver l'ID du plan en cours via la dernière séance planifiée
        if let lastSeance = seances.filter({ $0.statut == .planifie }).last {
            currentPlanId = lastSeance.planId ?? UUID().uuidString
        } else {
            currentPlanId = UUID().uuidString
        }
        
        // On insère juste un message de l'IA pour inviter à parler
        let welcomeMsg = ChatMessage(
            contenu: "Je suis prêt à adapter ton plan. Que souhaites-tu modifier ? (jours, intensité, durée...)",
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
                // 2. Appel API avec le contexte complet (toutes les séances)
                let (responseString, newSeances) = try await viewModel.sendMessage(
                    text,
                    history: messages,
                    athlete: athlete,
                    allSeances: seances // On passe tout, le ViewModel filtrera les 5 dernières effectuées
                )
                
                // 3. Sauvegarde réponse IA
                let aiMessage = ChatMessage(contenu: responseString, estUtilisateur: false)
                modelContext.insert(aiMessage)
                
                // 4. Gestion intelligente des séances (Versioning)
                if !newSeances.isEmpty {
                    handleNewSeances(newSeances)
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
        // -> Celles qui appartiennent au plan actuel
        // -> Qui sont encore "Planifiées" (pas effectuées)
        // -> Qui sont dans le futur (optionnel, pour sécurité)
        let seancesToDelete = seances.filter { existingSeance in
            existingSeance.planId == planId &&
            existingSeance.statut == .planifie &&
            existingSeance.date >= Calendar.current.startOfDay(for: Date())
        }
        
        // Suppression
        for s in seancesToDelete {
            modelContext.delete(s)
        }
        
        // 2. Ajouter les NOUVELLES séances
        for seanceIA in seancesIA {
            // On convertit et on attache le planId
            if let newSeance = seanceIA.toSeance(planId: planId) {
                modelContext.insert(newSeance)
            }
        }
        
        print("✅ Plan mis à jour (ID: \(planId)) : \(seancesToDelete.count) supprimées, \(seancesIA.count) ajoutées.")
    }
    
    private func regeneratePlan() {
        let request = ChatMessage(
            contenu: "Peux-tu me régénérer un plan d'entraînement sur les 3 prochaines semaines ?",
            estUtilisateur: true
        )
        modelContext.insert(request)
        
        isLoading = true
        
        Task {
            do {
                let (responseString, newSeances) = try await viewModel.sendMessage(
                    request.contenu,
                    history: messages,
                    athlete: athlete,
                    allSeances: seances
                )
                
                let aiMessage = ChatMessage(contenu: responseString, estUtilisateur: false)
                modelContext.insert(aiMessage)
                
                if !newSeances.isEmpty {
                    handleNewSeances(newSeances)
                }
                
            } catch {
                let errorMessage = ChatMessage.messageErreur()
                modelContext.insert(errorMessage)
            }
            
            isLoading = false
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
    
    private func clearChat() {
        for message in messages {
            modelContext.delete(message)
        }
        // On reset aussi l'ID du plan pour repartir de zéro
        currentPlanId = nil
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
