const express = require('express');
const cors = require('cors');
const config = require('./config/env');
const healthRoutes = require('./routes/healthRoutes');
const app = express();

// --- Middleware (runs on every request, in this order) ---
app.use(cors({ origin: config.clientUrl })); // only our frontend may call the API
app.use(express.json());                     // lets us read JSON request bodies

// --- Routes ---
// A simple endpoint to check that the server is alive (no database involved yet).
app.use('/api/health', healthRoutes);

// --- 404 handler: runs if no route above matched ---
app.use((req, res) => {
  res.status(404).json({ message: `Route not found: ${req.method} ${req.originalUrl}` });
});

// --- Error handler: Express recognises it by its 4 parameters ---
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ message: 'Internal server error' });
});

module.exports = app;