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
    const { messages, athlete, recentActivity } = req.body;

    if (!messages || !Array.isArray(messages)) {
      return res.status(400).json({ error: 'Messages array required' });
    }

    // On passe l'activité récente au prompt
    const systemPrompt = buildSystemPrompt(athlete, recentActivity);

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
        model: 'llama-3.1-8b-instant',
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
    /```json\s*([\s\S]*?)\s*```/,           // ```json ... ```
    /```\s*([\s\S]*?\[\s*\{[\s\S]*?\}\s*\][\s\S]*?)\s*```/, // ``` ... [] ... ```
    /(\[\s*\{\s*"date"[\s\S]*?\}\s*\])/,    // [ { "date" ... } ] directement
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
      // Récupérer la chaîne JSON
      let jsonStr = jsonMatch[1] || jsonMatch[0];
      
      // Nettoyer la chaîne
      jsonStr = jsonStr.trim();
      
      // Si ça ne commence pas par [, chercher le tableau
      if (!jsonStr.startsWith('[')) {
        const arrayMatch = jsonStr.match(/(\[\s*\{[\s\S]*\}\s*\])/);
        if (arrayMatch) {
          jsonStr = arrayMatch[1];
        }
      }
      
      // Parser le JSON
      const parsed = JSON.parse(jsonStr);
      
      // Vérifier que c'est bien un tableau de séances
      if (Array.isArray(parsed) && parsed.length > 0 && parsed[0].date) {
        seances = parsed;
        // Nettoyer le message pour ne pas afficher le JSON brut
        cleanMessage = content.replace(jsonMatch[0], '').trim();
        
        // Supprimer aussi les lignes vides multiples
        cleanMessage = cleanMessage.replace(/\n{3,}/g, '\n\n');
        
        // Message court de confirmation
        cleanMessage = `Parfait ! J'ai créé ton plan d'entraînement personnalisé. 🎯\n\nTu as ${seances.length} séances programmées. Consulte ton planning pour voir les détails !`;
      }
    } catch (e) {
      console.error("Erreur parsing JSON IA:", e.message);
      console.error("JSON tenté:", jsonMatch[1] || jsonMatch[0]);
    }
  }

  return { cleanMessage, seances };
}

function buildSystemPrompt(athlete, recentActivity) {
  // Date actuelle pour que l'IA génère les bonnes dates
  const today = new Date();
  const dateStr = today.toISOString().split('T')[0]; // Format YYYY-MM-DD
  const year = today.getFullYear();
  const month = today.getMonth() + 1;
  const day = today.getDate();

  let prompt = `Tu es un coach sportif IA expert et bienveillant. Tu aides les athlètes à atteindre leurs objectifs.

DATE ACTUELLE : ${dateStr} (${day}/${month}/${year})
IMPORTANT : Nous sommes en ${year}. Quand tu génères des séances, utilise l'année ${year} ou ${year + 1} selon les dates.

Ton style :
- Motivant mais réaliste
- Tu donnes des conseils concrets et personnalisés, assez synthétique
- Tu adaptes les entraînements selon le ressenti et la fatigue

RÈGLE FONDAMENTALE POUR LA CRÉATION DE PLANS :
Quand on te demande de créer un plan d'entraînement, tu DOIS créer UNE SÉANCE PAR JOUR pour les 2 prochaines semaines (14 jours).
Pour chaque jour, tu choisis entre :
- Un entraînement (Endurance, Seuil, VMA, Intervalles, Sortie Longue) 
- Tu dois détailler dans la description les allures ou les temps pour les exercices - regarde les activités précédentes pour connaitre l'allure du coureur sur x kilometres et donne des exercices adaptés.
IMPORTANT donne toutes les allures/vitesses en minutes par kilomètre.
- Un jour de repos (type "Repos" avec description "Repos complet" ou "Récupération active légère")

C'est très important d'avoir une séance pour CHAQUE jour du calendrier, même les jours de repos !

TRÈS IMPORTANT - FORMAT DES SÉANCES :
Tu DOIS fournir les séances dans un bloc JSON valide à la fin de ta réponse.
Ne fais PAS de long discours, juste une phrase pour dire que tu as generé le plan et que la personne peut le modifier par la suite, puis donne le JSON.

\`\`\`json
[
  {
    "date": "${year}-12-09",
    "type": "Endurance",
    "sport": "Course",
    "dureeMinutes": 45,
    "description": "Footing en aisance respiratoire, rythme conversationnel",
    "intensite": "Modéré"
  },
  {
    "date": "${year}-12-10",
    "type": "Repos",
    "sport": "Repos",
    "dureeMinutes": 0,
    "description": "Repos complet - récupération",
    "intensite": "Léger"
  }
]
\`\`\`

RÈGLES STRICTES POUR LE JSON :
- Les dates DOIVENT être au format YYYY-MM-DD avec l'année ${year} ou ${year + 1}
- Crée une séance pour CHAQUE jour (14 jours minimum pour 2 semaines)
- Types possibles : Endurance, Seuil, VMA, Intervalles, Sortie Longue, Récupération, Repos
- Intensité : Léger, Modéré, Intense, Maximal
- Pour les jours de repos : type="Repos", sport="Repos", dureeMinutes=0
- FERME le bloc avec \`\`\` après le JSON
- Pas de virgule après le dernier élément
`;

  // Ajout du contexte des dernières séances
  if (recentActivity && recentActivity.length > 0) {
    prompt += `\n\nDERNIÈRES SÉANCES RÉALISÉES :\n`;
    recentActivity.forEach(s => {
      prompt += `- ${s.date} (${s.sport}): ${s.type}, ${s.duree}min. Ressenti: ${s.ressenti}/10.`;
      if (s.distance > 0) prompt += ` Distance: ${s.distance}km.`;
      if (s.commentaire) prompt += ` Note: ${s.commentaire}`;
      prompt += `\n`;
    });
    prompt += `\nAdapte la charge selon ces retours (si ressenti difficile, allège).`;
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
    if (athlete.blessures) {
      prompt += `\n- Blessures/contraintes : ${athlete.blessures}`;
    }
  } else {
    prompt += `

L'athlète n'a pas encore de profil complet. Pose-lui quelques questions rapides :
- Son objectif principal et la date
- Son niveau actuel
- Ses disponibilités`;
  }

  return prompt;
}
