// /api/strava/callback.js
// Reçoit le code OAuth et l'échange contre un access token

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { code, state, error } = req.query;

  // Gestion des erreurs OAuth
  if (error) {
    console.error('Strava OAuth error:', error);
    // Redirige vers l'app avec erreur
    return res.redirect(`lockedin://strava/error?message=${encodeURIComponent(error)}`);
  }

  if (!code) {
    return res.status(400).json({ error: 'No authorization code provided' });
  }

  try {
    // Échanger le code contre un token
    const tokenResponse = await fetch('https://www.strava.com/oauth/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        client_id: process.env.STRAVA_CLIENT_ID,
        client_secret: process.env.STRAVA_CLIENT_SECRET,
        code: code,
        grant_type: 'authorization_code'
      })
    });

    if (!tokenResponse.ok) {
      const error = await tokenResponse.json();
      console.error('Token exchange error:', error);
      return res.redirect(`lockedin://strava/error?message=${encodeURIComponent('Token exchange failed')}`);
    }

    const tokenData = await tokenResponse.json();

    /*
    tokenData contient :
    {
      token_type: "Bearer",
      access_token: "xxx",
      refresh_token: "xxx",
      expires_at: 1234567890,
      athlete: { id, firstname, lastname, ... }
    }
    */

    // Option 1: Rediriger vers l'app iOS avec le token (deep link)
    // L'app devra gérer le scheme "lockedin://"
    const deepLink = `lockedin://strava/success?` +
      `access_token=${tokenData.access_token}` +
      `&refresh_token=${tokenData.refresh_token}` +
      `&expires_at=${tokenData.expires_at}` +
      `&athlete_id=${tokenData.athlete?.id || ''}`;

    // Option 2: Afficher une page HTML qui redirige
    const html = `
    <!DOCTYPE html>
    <html>
    <head>
      <title>Connexion Strava réussie</title>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          display: flex;
          justify-content: center;
          align-items: center;
          height: 100vh;
          margin: 0;
          background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
          color: white;
          text-align: center;
        }
        .container {
          padding: 40px;
          background: rgba(255,255,255,0.1);
          border-radius: 20px;
          backdrop-filter: blur(10px);
        }
        h1 { margin-bottom: 10px; }
        p { opacity: 0.9; }
        .success-icon {
          font-size: 60px;
          margin-bottom: 20px;
        }
        .button {
          display: inline-block;
          margin-top: 20px;
          padding: 15px 30px;
          background: white;
          color: #667eea;
          text-decoration: none;
          border-radius: 10px;
          font-weight: bold;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <div class="success-icon">✅</div>
        <h1>Connexion réussie !</h1>
        <p>Ton compte Strava est maintenant connecté à LockedIn.</p>
        <a href="${deepLink}" class="button">Retourner à l'app</a>
      </div>
      <script>
        // Essaie de rediriger automatiquement vers l'app
        setTimeout(() => {
          window.location.href = "${deepLink}";
        }, 1500);
      </script>
    </body>
    </html>
    `;

    res.setHeader('Content-Type', 'text/html');
    return res.status(200).send(html);

  } catch (error) {
    console.error('Callback error:', error);
    return res.redirect(`lockedin://strava/error?message=${encodeURIComponent('Server error')}`);
  }
}
