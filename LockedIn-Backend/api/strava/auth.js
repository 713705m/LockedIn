// /api/strava/auth.js
// Génère l'URL d'autorisation Strava

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const clientId = process.env.STRAVA_CLIENT_ID;
  
  if (!clientId) {
    return res.status(500).json({ error: 'Strava not configured' });
  }

  // L'URL de callback - à adapter selon ton déploiement
  const redirectUri = `${process.env.VERCEL_URL ? 'https://' + process.env.VERCEL_URL : 'http://localhost:3000'}/api/strava/callback`;
  
  // Scopes nécessaires pour lire les activités
  const scope = 'read,activity:read_all';
  
  // State pour sécuriser (en prod, génère un vrai token unique)
  const state = req.query.state || 'lockedin_auth';

  const authUrl = `https://www.strava.com/oauth/authorize?` +
    `client_id=${clientId}` +
    `&redirect_uri=${encodeURIComponent(redirectUri)}` +
    `&response_type=code` +
    `&scope=${scope}` +
    `&state=${state}`;

  return res.status(200).json({ 
    authUrl,
    message: 'Redirect user to authUrl to start OAuth flow'
  });
}
