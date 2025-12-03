import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.timestamp) private var messages: [ChatMessage]
    @Query private var athletes: [Athlete]
    
    @State private var viewModel = ChatViewModel()
    @State private var inputText = ""
    @State private var isLoading = false
    
    private var athlete: Athlete? { athletes.first }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Messages
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
            .navigationTitle("Coach IA 🏃")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Nouvelle conversation", systemImage: "plus.message") {
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
                setupInitialMessage()
            }
        }
    }
    
    // MARK: - Actions
    
    private func setupInitialMessage() {
        if messages.isEmpty {
            let welcome = ChatMessage.messageBienvenue()
            modelContext.insert(welcome)
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        // Ajouter le message utilisateur
        let userMessage = ChatMessage(contenu: text, estUtilisateur: true)
        modelContext.insert(userMessage)
        
        inputText = ""
        isLoading = true
        
        // Appeler l'API
        Task {
            do {
                let response = try await viewModel.sendMessage(
                    text,
                    history: messages,
                    athlete: athlete
                )
                
                let aiMessage = ChatMessage(contenu: response, estUtilisateur: false)
                modelContext.insert(aiMessage)
            } catch {
                let errorMessage = ChatMessage.messageErreur()
                modelContext.insert(errorMessage)
                print("Erreur API: \(error)")
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
        setupInitialMessage()
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
                let response = try await viewModel.sendMessage(
                    request.contenu,
                    history: messages,
                    athlete: athlete
                )
                
                let aiMessage = ChatMessage(contenu: response, estUtilisateur: false)
                modelContext.insert(aiMessage)
            } catch {
                let errorMessage = ChatMessage.messageErreur()
                modelContext.insert(errorMessage)
            }
            
            isLoading = false
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
