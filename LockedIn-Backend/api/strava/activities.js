// /api/strava/activities.js
// Récupère les activités de l'utilisateur depuis Strava

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Récupère le token depuis le header Authorization
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Access token required' });
  }

  const accessToken = authHeader.split(' ')[1];

  // Paramètres optionnels
  const { 
    before,      // Unix timestamp - activités avant cette date
    after,       // Unix timestamp - activités après cette date
    page = 1,    // Page number
    per_page = 30 // Nombre par page (max 200)
  } = req.query;

  try {
    // Construire l'URL avec les paramètres
    let url = `https://www.strava.com/api/v3/athlete/activities?page=${page}&per_page=${per_page}`;
    
    if (before) url += `&before=${before}`;
    if (after) url += `&after=${after}`;

    const response = await fetch(url, {
      headers: {
        'Authorization': `Bearer ${accessToken}`
      }
    });

    if (!response.ok) {
      if (response.status === 401) {
        return res.status(401).json({ 
          error: 'Token expired',
          code: 'TOKEN_EXPIRED'
        });
      }
      const error = await response.json();
      console.error('Strava API error:', error);
      return res.status(response.status).json({ error: 'Strava API error' });
    }

    const activities = await response.json();

    // Transformer les données pour notre app
    const formattedActivities = activities.map(activity => ({
      id: activity.id,
      name: activity.name,
      type: activity.type,                    // Run, Ride, Swim, etc.
      sport_type: activity.sport_type,        // Plus précis
      date: activity.start_date_local,
      distance: activity.distance,            // en mètres
      moving_time: activity.moving_time,      // en secondes
      elapsed_time: activity.elapsed_time,
      total_elevation_gain: activity.total_elevation_gain,
      average_speed: activity.average_speed,  // m/s
      max_speed: activity.max_speed,
      average_heartrate: activity.average_heartrate,
      max_heartrate: activity.max_heartrate,
      calories: activity.calories,
      suffer_score: activity.suffer_score,    // Score d'effort Strava
      map: activity.map?.summary_polyline,    // Polyline pour afficher la carte
      
      // Données calculées
      distance_km: (activity.distance / 1000).toFixed(2),
      pace_per_km: activity.moving_time && activity.distance 
        ? formatPace(activity.moving_time / (activity.distance / 1000))
        : null,
      duration_formatted: formatDuration(activity.moving_time)
    }));

    return res.status(200).json({
      activities: formattedActivities,
      count: formattedActivities.length,
      page: parseInt(page),
      per_page: parseInt(per_page)
    });

  } catch (error) {
    console.error('Activities fetch error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

// Formate une allure en min/km
function formatPace(secondsPerKm) {
  const minutes = Math.floor(secondsPerKm / 60);
  const seconds = Math.round(secondsPerKm % 60);
  return `${minutes}'${seconds.toString().padStart(2, '0')}`;
}

// Formate une durée en HH:MM:SS ou MM:SS
function formatDuration(seconds) {
  if (!seconds) return '--:--';
  
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;

  if (hours > 0) {
    return `${hours}h${minutes.toString().padStart(2, '0')}`;
  }
  return `${minutes}:${secs.toString().padStart(2, '0')}`;
}
