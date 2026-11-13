const { Pool } = require('pg');
const config = require('./env');

// The pool reads its connection details from our central config,
// which got them from .env. No credentials are written in this file.
const pool = new Pool({
  host: config.db.host,
  port: config.db.port,
  database: config.db.database,
  user: config.db.user,
  password: config.db.password,
  max: 10,                       // at most 10 connections open at once
  idleTimeoutMillis: 30000,      // close a connection that sits unused for 30s
  connectionTimeoutMillis: 5000, // give up if no connection is available in 5s
});

// If an idle connection breaks (e.g. PostgreSQL restarts), log it
// instead of letting the whole process crash with an unhandled error.
pool.on('error', (err) => {
  console.error('Unexpected PostgreSQL pool error:', err.message);
});

// Helper for ordinary queries: borrows a connection, runs the query,
// and returns the connection to the pool automatically.
const query = (text, params) => pool.query(text, params);

module.exports = { pool, query };