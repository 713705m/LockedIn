//
//  ProfilView.swift
//  LockedIn
//
//  Created by Marianne Ninet on 07/12/2025.
//

import SwiftUI
import SwiftData

struct ProfilView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var athletes: [Athlete]
    @Query(sort: \Seance.date) private var seances: [Seance]
    
    @StateObject private var stravaService = StravaService.shared
    
    @State private var showEditSheet = false
    @State private var showStravaAuth = false
    @State private var showRegeneratePlanAlert = false
    @State private var stravaAuthURL: URL?
    
    private var athlete: Athlete? { athletes.first }
    
    private var hasExistingPlan: Bool {
        seances.contains { $0.sourceAffichage == .ia && $0.statut == .planifie }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Header Card
                    if let athlete = athlete {
                        HeaderCard(athlete: athlete)
                    }
                    
                    // MARK: - Objectif Card
                    if let athlete = athlete {
                        ObjectifCard(athlete: athlete)
                    }
                    
                    // MARK: - VMA & Allures Card
                    if let athlete = athlete {
                        AlluresCard(athlete: athlete)
                    }
                    
                    // MARK: - Strava Card
                    StravaCard(
                        isConnected: stravaService.isConnected,
                        onConnect: { connectStrava() },
                        onDisconnect: { stravaService.disconnect() }
                    )
                    
                    // MARK: - Actions
                    VStack(spacing: 12) {
                        Button {
                            showEditSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "pencil")
                                Text("Modifier mon profil")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    Spacer(minLength: 40)
                }
                .padding(.top)
            }
            .navigationTitle("Mon Profil")
            .sheet(isPresented: $showEditSheet) {
                if let athlete = athlete {
                    EditProfilView(
                        athlete: athlete,
                        hasExistingPlan: hasExistingPlan,
                        onSave: { shouldRegenerate in
                            showEditSheet = false
                            if shouldRegenerate {
                                showRegeneratePlanAlert = true
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showStravaAuth) {
                if let url = stravaAuthURL {
                    StravaAuthView(url: url)
                }
            }
            .alert("Régénérer le plan ?", isPresented: $showRegeneratePlanAlert) {
                Button("Plus tard", role: .cancel) { }
                Button("Régénérer") {
                    // TODO: Navigate to Coach tab with regeneration
                }
            } message: {
                Text("Ton profil a été mis à jour. Veux-tu régénérer ton plan d'entraînement avec ces nouvelles informations ?")
            }
        }
    }
    
    private func connectStrava() {
        Task {
            do {
                let url = try await stravaService.startOAuth()
                stravaAuthURL = url
                showStravaAuth = true
            } catch {
                print("Erreur connexion Strava: \(error)")
            }
        }
    }
}

// MARK: - Header Card

struct HeaderCard: View {
    let athlete: Athlete
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 70, height: 70)
                
                Text(athlete.nom.prefix(1).uppercased())
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(athlete.nom.isEmpty ? "Athlète" : athlete.nom)
                    .font(.title2)
                    .fontWeight(.bold)
                
                if athlete.onboardingComplete {
                    Text("Membre depuis \(athlete.dateCreation.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Objectif Card

struct ObjectifCard: View {
    let athlete: Athlete
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "flag.fill")
                    .foregroundStyle(.orange)
                Text("Objectif")
                    .font(.headline)
                Spacer()
            }
            
            HStack(spacing: 20) {
                // Type d'objectif
                VStack(alignment: .leading, spacing: 4) {
                    Text(athlete.typeObjectif)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Course")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Date et countdown
                VStack(alignment: .trailing, spacing: 4) {
                    Text(athlete.dateObjectif.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 4) {
                        Text("\(athlete.joursRestants)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                        Text("jours")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Allures Card

struct AlluresCard: View {
    let athlete: Athlete
    
    // Calcul des allures basées sur la VMA
    private var alluresCalculees: (endurance: String, seuil: String, vma: String)? {
        guard let vma = athlete.vma, vma > 0 else { return nil }
        
        let allureVMA = 60.0 / vma
        let allureSeuil = 60.0 / (vma * 0.85)
        let allureEndurance = 60.0 / (vma * 0.70)
        
        return (
            formatAllure(allureEndurance),
            formatAllure(allureSeuil),
            formatAllure(allureVMA)
        )
    }
    
    private func formatAllure(_ minParKm: Double) -> String {
        let min = Int(minParKm)
        let sec = Int((minParKm - Double(min)) * 60)
        return "\(min)'\(String(format: "%02d", sec))"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "speedometer")
                    .foregroundStyle(.blue)
                Text("VMA & Allures")
                    .font(.headline)
                Spacer()
            }
            
            if let vma = athlete.vma {
                // VMA
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VMA")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f km/h", vma))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                    }
                    
                    Spacer()
                    
                    // Badge source
                    if athlete.allureEndurance != nil {
                        Text("Personnalisé")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    } else {
                        Text("Calculé")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                
                Divider()
                
                // Allures
                if let allures = alluresCalculees {
                    HStack(spacing: 0) {
                        AllureItem(
                            label: "Endurance",
                            value: athlete.allureEndurance != nil ? Athlete.formatAllure(athlete.allureEndurance) : allures.endurance,
                            color: .green
                        )
                        
                        Divider()
                            .frame(height: 40)
                        
                        AllureItem(
                            label: "Seuil",
                            value: athlete.allureSeuil != nil ? Athlete.formatAllure(athlete.allureSeuil) : allures.seuil,
                            color: .orange
                        )
                        
                        Divider()
                            .frame(height: 40)
                        
                        AllureItem(
                            label: "VMA",
                            value: athlete.allureVMA != nil ? Athlete.formatAllure(athlete.allureVMA) : allures.vma,
                            color: .red
                        )
                    }
                }
                
            } else {
                // Pas de VMA
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    
                    Text("VMA non renseignée")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("Modifie ton profil pour ajouter ta VMA ou un temps de course récent")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

struct AllureItem: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text("/km")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Strava Card

struct StravaCard: View {
    let isConnected: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "figure.run")
                    .foregroundStyle(.orange)
                Text("Strava")
                    .font(.headline)
                Spacer()
                
                // Status badge
                if isConnected {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Connecté")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            
            if isConnected {
                // Connecté
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Compte lié")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("Tes activités sont synchronisées automatiquement")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                
                Button(role: .destructive) {
                    onDisconnect()
                } label: {
                    HStack {
                        Image(systemName: "link.badge.xmark")
                        Text("Se déconnecter")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1))
                    .foregroundStyle(.red)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            } else {
                // Non connecté
                VStack(spacing: 12) {
                    Text("Connecte ton compte Strava pour synchroniser automatiquement tes activités et améliorer les recommandations de ton coach IA.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        onConnect()
                    } label: {
                        HStack {
                            Image(systemName: "link")
                            Text("Connecter Strava")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}

// MARK: - Edit Profil View

struct EditProfilView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var athlete: Athlete
    let hasExistingPlan: Bool
    let onSave: (Bool) -> Void
    
    // Local state pour l'édition
    @State private var nom: String = ""
    @State private var typeObjectif: String = "Marathon"
    @State private var dateObjectif: Date = Date()
    
    // VMA - mode de saisie
    @State private var vmaMode: VMAMode = .direct
    @State private var vmaDirecte: String = ""
    
    // Pour calcul via temps de course
    @State private var distanceReference: String = "10 km"
    @State private var tempsHeures: String = ""
    @State private var tempsMinutes: String = ""
    @State private var tempsSecondes: String = ""
    
    // Allures personnalisées (optionnel)
    @State private var useCustomAllures: Bool = false
    @State private var allureEndurance: String = ""
    @State private var allureSeuil: String = ""
    
    // Track si des changements importants ont été faits
    @State private var hasSignificantChanges: Bool = false
    
    enum VMAMode: String, CaseIterable {
        case direct = "Je connais ma VMA"
        case fromTime = "Calculer depuis un temps"
        case fromLevel = "Estimer selon mon niveau"
    }
    
    let typesObjectifs = ["Marathon", "Semi-Marathon", "10 km", "Trail", "Triathlon", "5 km", "Autre"]
    let distances = ["5 km", "10 km", "Semi-marathon", "Marathon"]
    let niveaux: [(id: String, titre: String, vma: Double)] = [
        ("debutant", "Débutant", 13),
        ("intermediaire", "Intermédiaire", 15),
        ("confirme", "Confirmé", 17),
        ("expert", "Expert", 19)
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
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Infos de base
                Section("Informations") {
                    TextField("Prénom", text: $nom)
                }
                
                // MARK: - Objectif
                Section("Objectif") {
                    Picker("Type", selection: $typeObjectif) {
                        ForEach(typesObjectifs, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    
                    DatePicker("Date", selection: $dateObjectif, in: Date()..., displayedComponents: .date)
                }
                
                // MARK: - VMA
                Section {
                    Picker("Comment renseigner ta VMA ?", selection: $vmaMode) {
                        ForEach(VMAMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    switch vmaMode {
                    case .direct:
                        HStack {
                            Text("VMA")
                            Spacer()
                            TextField("16.5", text: $vmaDirecte)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                            Text("km/h")
                                .foregroundStyle(.secondary)
                        }
                        
                    case .fromTime:
                        Picker("Distance", selection: $distanceReference) {
                            ForEach(distances, id: \.self) { d in
                                Text(d).tag(d)
                            }
                        }
                        
                        HStack {
                            Text("Temps")
                            Spacer()
                            TextField("H", text: $tempsHeures)
                                .keyboardType(.numberPad)
                                .frame(width: 40)
                                .multilineTextAlignment(.center)
                            Text("h")
                            TextField("MM", text: $tempsMinutes)
                                .keyboardType(.numberPad)
                                .frame(width: 40)
                                .multilineTextAlignment(.center)
                            Text("m")
                            TextField("SS", text: $tempsSecondes)
                                .keyboardType(.numberPad)
                                .frame(width: 40)
                                .multilineTextAlignment(.center)
                            Text("s")
                        }
                        
                        if let vma = vmaCalculee {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.orange)
                                Text("VMA estimée : ")
                                Text(String(format: "%.1f km/h", vma))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.orange)
                            }
                        }
                        
                    case .fromLevel:
                        ForEach(niveaux, id: \.id) { niveau in
                            Button {
                                vmaDirecte = String(format: "%.1f", niveau.vma)
                            } label: {
                                HStack {
                                    Text(niveau.titre)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(Int(niveau.vma)) km/h")
                                        .foregroundStyle(.secondary)
                                    if vmaDirecte == String(format: "%.1f", niveau.vma) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("VMA")
                } footer: {
                    Text("Ta VMA permet de calculer automatiquement tes allures d'entraînement.")
                }
                
                // MARK: - Allures personnalisées
                Section {
                    Toggle("Personnaliser mes allures", isOn: $useCustomAllures)
                    
                    if useCustomAllures {
                        HStack {
                            Text("Endurance")
                            Spacer()
                            TextField("5'45", text: $allureEndurance)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("/km")
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack {
                            Text("Seuil")
                            Spacer()
                            TextField("4'50", text: $allureSeuil)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("/km")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Allures (optionnel)")
                } footer: {
                    Text("Si tu ne personnalises pas, les allures seront calculées automatiquement depuis ta VMA.")
                }
            }
            .navigationTitle("Modifier le profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        saveChanges()
                    }
                    .bold()
                }
            }
            .onAppear {
                loadCurrentValues()
            }
        }
    }
    
    private func loadCurrentValues() {
        nom = athlete.nom
        typeObjectif = athlete.typeObjectif
        dateObjectif = athlete.dateObjectif
        
        if let vma = athlete.vma {
            vmaDirecte = String(format: "%.1f", vma)
            vmaMode = .direct
        }
        
        if let allure = athlete.allureEndurance {
            allureEndurance = Athlete.formatAllure(allure)
            useCustomAllures = true
        }
        if let allure = athlete.allureSeuil {
            allureSeuil = Athlete.formatAllure(allure)
            useCustomAllures = true
        }
    }
    
    private func saveChanges() {
        // Détecter changements significatifs
        let oldVMA = athlete.vma
        let oldObjectif = athlete.typeObjectif
        let oldDate = athlete.dateObjectif
        
        // Appliquer les changements
        athlete.nom = nom
        athlete.typeObjectif = typeObjectif
        athlete.dateObjectif = dateObjectif
        
        // VMA
        switch vmaMode {
        case .direct, .fromLevel:
            if let vma = Double(vmaDirecte.replacingOccurrences(of: ",", with: ".")) {
                athlete.vma = vma
            }
        case .fromTime:
            if let vma = vmaCalculee {
                athlete.vma = vma
            }
        }
        
        // Allures
        if useCustomAllures {
            if let allure = Athlete.parseAllure(allureEndurance) {
                athlete.allureEndurance = allure
            }
            if let allure = Athlete.parseAllure(allureSeuil) {
                athlete.allureSeuil = allure
            }
        } else {
            // Reset les allures personnalisées pour utiliser le calcul auto
            athlete.allureEndurance = nil
            athlete.allureSeuil = nil
            athlete.allureVMA = nil
        }
        
        // Vérifier si changements significatifs
        let significantChanges = (oldVMA != athlete.vma) ||
                                 (oldObjectif != athlete.typeObjectif) ||
                                 (oldDate != athlete.dateObjectif)
        
        onSave(significantChanges && hasExistingPlan)
    }
}

// MARK: - Strava Auth View (WebView simple)

struct StravaAuthView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            WebView(url: url)
                .navigationTitle("Connexion Strava")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - WebView pour OAuth

import WebKit

struct WebView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Intercepter le callback de Strava
            if let url = navigationAction.request.url,
               url.scheme == "lockedin" {
                StravaService.shared.handleCallback(url: url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

#Preview {
    ProfilView()
        .modelContainer(for: [Athlete.self, Seance.self, ChatMessage.self], inMemory: true)
}
