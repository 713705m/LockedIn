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
    const { messages, athlete } = req.body;

    if (!messages || !Array.isArray(messages)) {
      return res.status(400).json({ error: 'Messages array required' });
    }

    // Build system prompt
    const systemPrompt = buildSystemPrompt(athlete);

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
        model: 'meta-llama/llama-guard-4-12b',
        messages: apiMessages,
        temperature: 0.7,
        max_tokens: 1024
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

    return res.status(200).json({ 
      message: content,
      usage: data.usage
    });

  } catch (error) {
    console.error('Chat API error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

// Build the system prompt based on athlete profile
function buildSystemPrompt(athlete) {
  let prompt = `Tu es un coach sportif IA expert et bienveillant. Tu aides les athlètes à atteindre leurs objectifs.

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

Format des séances que tu proposes :
- Type (Endurance, Seuil, VMA, Intervalles, Sortie Longue, etc.)
- Durée
- Description détaillée
- Allure cible si pertinent
`;

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
