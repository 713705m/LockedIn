// /api/chat.js
// Proxy sécurisé vers l'API Groq pour le chat avec le coach IA

export default async function handler(req, res) {
  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Only POST allowed
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { messages, athlete, recentActivity, wizardContext, isAdjustmentMode, plannedSeances } = req.body;

    if (!messages || !Array.isArray(messages)) {
      return res.status(400).json({ error: 'Messages array required' });
    }

    // On passe l'activité récente et le contexte wizard au prompt
    const systemPrompt = buildSystemPrompt(athlete, recentActivity, wizardContext, isAdjustmentMode, plannedSeances);

    // Prepare messages for Groq
    const apiMessages = [
      { role: 'system', content: systemPrompt },
      ...messages.slice(-20) // Keep last 20 messages
    ];
    
    // Call Groq API
    const groqResponse = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${process.env.GROQ_API_KEY}`
      },
      body: JSON.stringify({
        model: 'llama-3.3-70b-versatile',
        messages: apiMessages,
        temperature: 0.7,
        max_tokens: 4096
      })
    });

    if (!groqResponse.ok) {
      const error = await groqResponse.json();
      console.error('Groq API error:', error);
      return res.status(groqResponse.status).json({
        error: error.error?.message || 'Groq API error'
      });
    }

    const data = await groqResponse.json();
    const content = data.choices?.[0]?.message?.content;

    if (!content) {
      return res.status(500).json({ error: 'No response from AI' });
    }

    // Parsing des séances côté serveur
    const { cleanMessage, seances } = parseContent(content);

    // Vérification du nombre de séances
    if (seances.length > 0 && seances.length < 14) {
      console.warn(`⚠️ Seulement ${seances.length} séances générées au lieu de 14`);
    }
    
    console.log(`✅ Parsed ${seances.length} séances from AI response`);

    return res.status(200).json({
      message: cleanMessage,
      seances: seances,
      usage: data.usage
    });

  } catch (error) {
    console.error('Chat API error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

// Fonction pour extraire le JSON de la réponse textuelle
function parseContent(content) {
  let seances = [];
  let cleanMessage = content;

  // Plusieurs patterns pour détecter le JSON
  const patterns = [
    /```json\s*([\s\S]*?)\s*```/,
    /```\s*([\s\S]*?\[\s*\{[\s\S]*?\}\s*\][\s\S]*?)\s*```/,
    /(\[\s*\{\s*"date"[\s\S]*?\}\s*\])/,
  ];

  let jsonMatch = null;

  for (const pattern of patterns) {
    const match = content.match(pattern);
    if (match) {
      jsonMatch = match;
      break;
    }
  }

  if (jsonMatch) {
    try {
      let jsonStr = jsonMatch[1] || jsonMatch[0];
      jsonStr = jsonStr.trim();
      
      if (!jsonStr.startsWith('[')) {
        const arrayMatch = jsonStr.match(/(\[\s*\{[\s\S]*\}\s*\])/);
        if (arrayMatch) {
          jsonStr = arrayMatch[1];
        }
      }
      
      const parsed = JSON.parse(jsonStr);
      
      if (Array.isArray(parsed) && parsed.length > 0 && parsed[0].date) {
        seances = parsed;
        cleanMessage = content.replace(jsonMatch[0], '').trim();
        cleanMessage = cleanMessage.replace(/\n{3,}/g, '\n\n');
        cleanMessage = `Parfait ! J'ai créé ton plan d'entraînement personnalisé. 🎯\n\nTu as ${seances.length} séances programmées. Consulte ton planning pour voir les détails !`;
      }
    } catch (e) {
      console.error("Erreur parsing JSON IA:", e.message);
      console.error("JSON tenté:", jsonMatch[1] || jsonMatch[0]);
    }
  }

  return { cleanMessage, seances };
}

// Génère la liste des 14 prochains jours au format YYYY-MM-DD
function generateNext14Days(startDate) {
  const days = [];
  const joursSemaine = ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
  
  for (let i = 0; i < 14; i++) {
    const date = new Date(startDate);
    date.setDate(date.getDate() + i);
    
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    const jourNom = joursSemaine[date.getDay()];
    const semaine = i < 7 ? 'Semaine 1' : 'Semaine 2';
    
    days.push(`${i + 1}. ${year}-${month}-${day} (${jourNom} - ${semaine})`);
  }
  
  return days.join('\n');
}

function buildSystemPrompt(athlete, recentActivity, wizardContext, isAdjustmentMode = false, plannedSeances = []) {
  // Date actuelle pour que l'IA génère les bonnes dates
  const today = new Date();
  const dateStr = today.toISOString().split('T')[0];
  const year = today.getFullYear();
  const month = today.getMonth() + 1;
  const day = today.getDate();

  // Calculer la date de début (soit du wizard, soit aujourd'hui)
  let startDate = today;
  if (wizardContext?.dateDebut) {
    startDate = new Date(wizardContext.dateDebut);
  }
  const startDateStr = startDate.toISOString().split('T')[0];
  const startYear = startDate.getFullYear();
  const startMonth = startDate.getMonth() + 1;
  const startDay = startDate.getDate();

  let prompt = `Tu es un coach sportif IA expert et bienveillant. Tu aides les athlètes à atteindre leurs objectifs.

DATE ACTUELLE : ${dateStr} (${day}/${month}/${year})
IMPORTANT : Nous sommes en ${year}. Quand tu génères des séances, utilise l'année ${startYear} selon les dates.

Ton style :
- Motivant mais réaliste
- Tu donnes des conseils concrets et personnalisés, assez synthétique
- Tu adaptes les entraînements selon le ressenti et la fatigue

RÈGLE FONDAMENTALE POUR LA CRÉATION DE PLANS :
Quand on te demande de créer un plan d'entraînement, tu DOIS créer UNE SÉANCE PAR JOUR pour les 2 prochaines semaines (14 jours).
La PREMIÈRE séance doit être le ${startDateStr} (${startDay}/${startMonth}/${startYear}).

Pour chaque jour, tu choisis entre :
- Un entraînement (Endurance, Seuil, VMA, Intervalles, Sortie Longue) 
- Un jour de repos (type "Repos" avec description "Repos complet" ou "Récupération active légère")

⚠️ RÈGLE OBLIGATOIRE SUR LES ALLURES ⚠️
Tu DOIS TOUJOURS inclure les allures précises dans la description de CHAQUE séance (sauf repos).
Format des allures : TOUJOURS en min/km (ex: "5'30/km", "4'45/km")

Exemples de descriptions CORRECTES :
- Endurance : "Footing 45min à 5'45-6'00/km, aisance respiratoire"
- Seuil : "3x10min à 4'30/km avec 3min récup trot à 6'00/km"
- VMA : "10x400m à 3'30/km (récup 200m trot à 6'00/km)"
- Intervalles : "6x1000m à 4'00/km, récup 2min marche"
- Sortie longue : "1h30 à 5'50-6'10/km, ravito eau toutes les 30min"

Exemples de descriptions INCORRECTES (à ne JAMAIS faire) :
- "Footing en aisance" ❌ (pas d'allure)
- "Séance de seuil" ❌ (pas d'allure)
- "Fractionné" ❌ (pas de détails)

Si tu ne connais pas les allures de l'athlète, utilise des fourchettes raisonnables basées sur son niveau.

POUR LES MODIFICATIONS DE SÉANCES :
Quand l'utilisateur demande de modifier une séance existante, tu DOIS aussi inclure les allures dans ta proposition.
Par exemple si on te demande "décale ma séance de mardi", tu dois redonner la description complète AVEC les allures.

C'est très important d'avoir une séance pour CHAQUE jour du calendrier, même les jours de repos !

`;

  // ========== MODE AJUSTEMENT ==========
  if (isAdjustmentMode && plannedSeances && plannedSeances.length > 0) {
    prompt += `
=== MODE AJUSTEMENT DE PLAN ===
L'utilisateur veut MODIFIER son plan existant. Voici ses séances actuelles :

`;
    plannedSeances.forEach((s, i) => {
      prompt += `${i + 1}. ${s.date} - ${s.type} (${s.sport}) - ${s.dureeMinutes}min - "${s.description}"\n`;
    });
    
    prompt += `
INSTRUCTIONS POUR L'AJUSTEMENT :
1. Écoute attentivement ce que l'utilisateur veut changer
2. Quand il te demande une modification (changer les jours, décaler, alléger, etc.), tu DOIS régénérer le plan
3. Garde les mêmes dates que le plan actuel (du ${plannedSeances[0]?.date} au ${plannedSeances[plannedSeances.length - 1]?.date})
4. Applique les modifications demandées par l'utilisateur
5. TOUJOURS inclure les allures dans les descriptions

⚠️ RÈGLE ABSOLUE - FORMAT DE RÉPONSE ⚠️
Tu ne dois JAMAIS lister les séances en texte brut comme "1. 2025-12-08 - Endurance..."
Tu DOIS TOUJOURS fournir les séances dans un bloc JSON valide comme ceci :

\`\`\`json
[
  {"date": "2025-12-08", "type": "Endurance", "sport": "Course", "dureeMinutes": 45, "description": "Footing 45min à 5'30-6'00/km", "intensite": "Modéré"},
  {"date": "2025-12-09", "type": "Repos", "sport": "Repos", "dureeMinutes": 0, "description": "Repos complet", "intensite": "Léger"}
]
\`\`\`

IMPORTANT : 
- Le JSON doit être entre \`\`\`json et \`\`\`
- Chaque séance doit avoir : date, type, sport, dureeMinutes, description, intensite
- Si l'utilisateur demande "pas de séance le mardi", mets type="Repos" pour les mardis
- Génère TOUTES les séances du plan (${plannedSeances.length} séances), pas juste celles modifiées
- Une phrase courte avant le JSON, pas de liste en texte !

`;
  } else {
    // Mode création normal
    prompt += `
TRÈS IMPORTANT - FORMAT DES SÉANCES :
Tu DOIS fournir les séances dans un bloc JSON valide à la fin de ta réponse.
Ne fais PAS de long discours, juste une phrase pour dire que tu as généré le plan, puis donne le JSON.

VOICI LES 14 DATES EXACTES QUE TU DOIS UTILISER (ne change PAS ces dates) :
${generateNext14Days(startDate)}

Pour CHAQUE date ci-dessus, crée une séance avec ce format :
\`\`\`json
[
  {
    "date": "YYYY-MM-DD",
    "type": "Endurance|Seuil|VMA|Intervalles|Sortie Longue|Récupération|Repos",
    "sport": "Course|Repos",
    "dureeMinutes": 45,
    "description": "Description AVEC allures en min/km",
    "intensite": "Léger|Modéré|Intense|Maximal"
  }
]
\`\`\`

RÈGLES STRICTES :
- Tu DOIS générer EXACTEMENT 14 séances, une pour chaque date listée ci-dessus
- Pour les jours de repos : type="Repos", sport="Repos", dureeMinutes=0
- FERME le bloc avec \`\`\` après le JSON
- Pas de virgule après le dernier élément
`;
  } // Fin du else (mode création normal)

  // Ajout des précisions du wizard si présentes
  if (wizardContext) {
    prompt += `\n\n=== CONTEXTE DE GÉNÉRATION (WIZARD) ===\n`;
    
    if (wizardContext.precisions) {
      prompt += `PRÉCISIONS IMPORTANTES DE L'UTILISATEUR : ${wizardContext.precisions}\n`;
      prompt += `Tu DOIS adapter le plan en fonction de ces précisions !\n`;
    }
    
    if (wizardContext.nouveauTypeObjectif) {
      prompt += `Nouvel objectif : ${wizardContext.nouveauTypeObjectif}\n`;
    }
    if (wizardContext.nouvelleDateObjectif) {
      const objDate = new Date(wizardContext.nouvelleDateObjectif);
      prompt += `Date de l'objectif : ${objDate.toLocaleDateString('fr-FR')}\n`;
    }
    if (wizardContext.allureEndurance) {
      prompt += `Allure endurance souhaitée : ${wizardContext.allureEndurance}/km\n`;
    }
    if (wizardContext.allureSeuil) {
      prompt += `Allure seuil souhaitée : ${wizardContext.allureSeuil}/km\n`;
    }
    if (wizardContext.vma) {
      prompt += `VMA : ${wizardContext.vma} km/h\n`;
      
      // Calculer les allures de référence
      const vma = parseFloat(wizardContext.vma);
      if (!isNaN(vma) && vma > 0) {
        const allureVMA = 60 / vma;
        const allureSeuil = 60 / (vma * 0.85);
        const allureEndurance = 60 / (vma * 0.70);
        
        const formatAllure = (minParKm) => {
          const min = Math.floor(minParKm);
          const sec = Math.round((minParKm - min) * 60);
          return `${min}'${sec.toString().padStart(2, '0')}`;
        };
        
        prompt += `\n📊 ALLURES CALCULÉES (VMA ${vma} km/h) : VMA=${formatAllure(allureVMA)}/km, Seuil=${formatAllure(allureSeuil)}/km, Endurance=${formatAllure(allureEndurance)}/km\n`;
        prompt += `UTILISE CES ALLURES dans toutes les descriptions de séances !\n`;
      }
    }
    
    // Gestion du mode d'estimation si pas de VMA directe
    if (wizardContext.estimationMode) {
      prompt += `\nMODE D'ESTIMATION DES ALLURES : ${wizardContext.estimationMode}\n`;
      
      if (wizardContext.estimationMode === 'niveau') {
        const niveauAllures = {
          debutant: { vma: 13, endurance: "6'30-7'00", seuil: "5'30-5'50" },
          intermediaire: { vma: 15, endurance: "5'30-6'00", seuil: "4'45-5'00" },
          confirme: { vma: 17, endurance: "5'00-5'20", seuil: "4'15-4'30" },
          expert: { vma: 19, endurance: "4'30-4'50", seuil: "3'50-4'05" }
        };
        
        const niveau = wizardContext.niveauEstime || 'intermediaire';
        const allures = niveauAllures[niveau] || niveauAllures.intermediaire;
        
        prompt += `Niveau déclaré : ${niveau}\n`;
        prompt += `📊 ALLURES À UTILISER : Endurance=${allures.endurance}/km, Seuil=${allures.seuil}/km\n`;
        prompt += `UTILISE CES ALLURES dans toutes les descriptions de séances !\n`;
      }
      
      if (wizardContext.estimationMode === 'temps' && wizardContext.tempsReference) {
        prompt += `Temps de référence sur ${wizardContext.distanceReference} : ${wizardContext.tempsReference}\n`;
        prompt += `Calcule les allures appropriées basées sur ce temps.\n`;
      }
      
      if (wizardContext.estimationMode === 'inconnu') {
        prompt += `L'athlète ne connaît pas sa VMA. Utilise des allures pour un niveau intermédiaire :\n`;
        prompt += `📊 ALLURES À UTILISER : Endurance=5'45-6'15/km, Seuil=4'50-5'10/km\n`;
        prompt += `Propose des fourchettes larges et précise que l'athlète devra ajuster selon son ressenti.\n`;
      }
    }
  }

  // Ajout du contexte des dernières séances
  if (recentActivity && recentActivity.length > 0) {
    prompt += `\n\nDERNIÈRES SÉANCES RÉALISÉES :\n`;
    recentActivity.forEach(s => {
      prompt += `- ${s.date} (${s.sport}): ${s.type}, ${s.duree}min. Ressenti: ${s.ressenti}/10.`;
      if (s.distance > 0) prompt += ` Distance: ${s.distance}km.`;
      if (s.vitesse > 0) prompt += ` Vitesse moyenne: ${s.vitesse}km/h.`;
      if (s.commentaire) prompt += ` Note: ${s.commentaire}`;
      prompt += `\n`;
    });
    prompt += `\nAdapte la charge selon ces retours (si ressenti difficile, allège). Utilise les vitesses moyennes pour ajuster les allures proposées.`;
  }

  // Si l'athlète a des infos dans son profil
  if (athlete && athlete.onboardingComplete) {
    prompt += `

PROFIL DE L'ATHLÈTE :
- Prénom : ${athlete.nom || 'Athlète'}
- Objectif : ${athlete.typeObjectif || 'Non défini'}
- Date objectif : ${athlete.dateObjectif || 'Non définie'}
- Semaines restantes : ${athlete.semainesRestantes || '?'}
- Heures d'entraînement/semaine : ${athlete.heuresParSemaine || '?'}h
- Sports pratiqués : ${athlete.sports?.join(', ') || 'Course'}`;

    if (athlete.vma) {
      prompt += `\n- VMA : ${athlete.vma} km/h`;
    }
    if (athlete.allureEndurance) {
      prompt += `\n- Allure endurance : ${athlete.allureEndurance}`;
    }
    if (athlete.allureSeuil) {
      prompt += `\n- Allure seuil : ${athlete.allureSeuil}`;
    }
    if (athlete.blessures) {
      prompt += `\n- Blessures/contraintes : ${athlete.blessures}`;
    }
    
    // Calculer les allures de référence si VMA connue
    if (athlete.vma) {
      const vma = parseFloat(athlete.vma);
      // Formules classiques basées sur %VMA
      const allureVMA = 60 / vma; // min/km à 100% VMA
      const allureSeuil = 60 / (vma * 0.85); // ~85% VMA
      const allureEndurance = 60 / (vma * 0.70); // ~70% VMA
      
      const formatAllure = (minParKm) => {
        const min = Math.floor(minParKm);
        const sec = Math.round((minParKm - min) * 60);
        return `${min}'${sec.toString().padStart(2, '0')}`;
      };
      
      prompt += `\n\n📊 ALLURES DE RÉFÉRENCE CALCULÉES (basées sur VMA ${vma} km/h) :`;
      prompt += `\n- Allure VMA (100%) : ${formatAllure(allureVMA)}/km`;
      prompt += `\n- Allure Seuil (~85%) : ${formatAllure(allureSeuil)}/km`;
      prompt += `\n- Allure Endurance (~70%) : ${formatAllure(allureEndurance)}/km`;
      prompt += `\nUTILISE CES ALLURES comme référence dans tes descriptions de séances !`;
    }
  } else {
    prompt += `

L'athlète n'a pas encore de profil complet. Génère un plan adapté à un coureur de niveau intermédiaire.`;
  }

  // Rappel final important
  prompt += `

=== RAPPEL FINAL ===
Quand tu génères ou modifies un plan, tu DOIS OBLIGATOIREMENT terminer ta réponse par un bloc JSON valide :
\`\`\`json
[{"date": "...", "type": "...", "sport": "...", "dureeMinutes": ..., "description": "...", "intensite": "..."}, ...]
\`\`\`
Sans ce JSON, les séances ne seront PAS enregistrées dans le planning de l'utilisateur !
Ne liste JAMAIS les séances en texte brut (1. 2025-12-08 - ...), uniquement en JSON.`;

  return prompt;
}
