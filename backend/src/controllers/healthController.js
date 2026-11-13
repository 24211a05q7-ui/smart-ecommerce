const { query } = require('../config/db');
const config = require('../config/env');

// GET /api/health  (moved here from app.js, same response as before)
const checkServer = (req, res) => {
  res.status(200).json({
    status: 'ok',
    message: 'Smart Commerce API is running',
  });
};

// GET /api/health/db
// Runs a harmless query to prove the database connection works.
const checkDatabase = async (req, res) => {
  try {
    const result = await query(
      'SELECT current_database() AS database, current_user AS "user", NOW() AS server_time'
    );
    const row = result.rows[0];

    res.status(200).json({
      status: 'ok',
      database: row.database,
      user: row.user,
      serverTime: row.server_time,
    });
  } catch (err) {
    // Full details go to the terminal, where only you can see them.
    console.error('Database health check failed:', err.message);

    const body = { status: 'error', message: 'Database connection failed' };
    // In development we also show the reason, to make debugging easier.
    // In production this is never sent to the client.
    if (config.nodeEnv === 'development') {
      body.reason = err.message;
    }

    res.status(503).json(body); // 503 = service unavailable
  }
};

module.exports = { checkServer, checkDatabase };