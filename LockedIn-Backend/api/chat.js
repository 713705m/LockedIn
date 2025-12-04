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
        max_tokens: 2048
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
  let matchedPattern = null;

  for (const pattern of patterns) {
    const match = content.match(pattern);
    if (match) {
      jsonMatch = match;
      matchedPattern = pattern;
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
- Tu utilises des emojis avec modération 🏃‍♂️
- Tu donnes des conseils concrets et personnalisés
- Tu poses des questions pour mieux comprendre l'athlète
- Tu adaptes les entraînements selon le ressenti

Tu peux :
- Créer des plans d'entraînement sur 3 semaines
- Expliquer les différents types de séances
- Ajuster le plan selon la fatigue/blessures
- Donner des conseils de nutrition et récupération
- Analyser les performances

TRÈS IMPORTANT - FORMAT DES SÉANCES :
Quand tu proposes des séances d'entraînement, tu DOIS les fournir dans un bloc JSON à la fin de ta réponse.
Le JSON doit être valide et complet. Utilise EXACTEMENT ce format :

\`\`\`json
[
  {
    "date": "${year}-12-09",
    "type": "Endurance",
    "sport": "Course",
    "dureeMinutes": 45,
    "description": "Footing en aisance respiratoire",
    "intensite": "Modéré"
  }
]
\`\`\`

RÈGLES POUR LE JSON :
- Les dates DOIVENT être au format YYYY-MM-DD avec l'année ${year} ou ${year + 1}
- Le type doit être : Endurance, Seuil, VMA, Intervalles, Sortie Longue, Récupération, Renforcement, Repos
- L'intensité doit être : Léger, Modéré, Intense, Maximal
- Assure-toi de FERMER le bloc avec \`\`\` après le JSON
- Ne mets PAS de virgule après le dernier élément du tableau
`;

  // Ajout du contexte des dernières séances
  if (recentActivity && recentActivity.length > 0) {
    prompt += `\n\nDERNIÈRES SÉANCES RÉALISÉES PAR L'ATHLÈTE :\n`;
    recentActivity.forEach(s => {
      prompt += `- ${s.date} (${s.sport}): ${s.type}, ${s.duree}min. Ressenti: ${s.ressenti}/10.`;
      if (s.distance > 0) prompt += ` Distance: ${s.distance}km.`;
      if (s.vitesse > 0) prompt += ` Vitesse moy: ${s.vitesse}km/h.`;
      if (s.commentaire) prompt += ` Commentaire: ${s.commentaire}`;
      prompt += `\n`;
    });
    prompt += `\nUtilise ces infos pour adapter la charge d'entraînement (si ressenti difficile, allège le plan).`;
  }

  // Si l'athlète a des infos dans son profil
  if (athlete && athlete.onboardingComplete) {
    prompt += `

PROFIL DE L'ATHLÈTE :
- Prénom : ${athlete.nom || 'Non renseigné'}
- Objectif : ${athlete.typeObjectif || 'Non défini'}
- Date objectif : ${athlete.dateObjectif || 'Non définie'}
- Semaines restantes : ${athlete.semainesRestantes || '?'}
- Heures d'entraînement/semaine : ${athlete.heuresParSemaine || '?'}h
- Sports : ${athlete.sports?.join(', ') || 'Course'}`;

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

L'athlète n'a pas encore rempli son profil complet. Commence par lui poser des questions pour mieux le connaître :
- Son objectif principal
- La date de sa compétition/objectif
- Son niveau actuel et expérience
- Ses disponibilités pour s'entraîner`;
  }

  return prompt;
}
