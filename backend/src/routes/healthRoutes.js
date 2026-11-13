const express = require('express');
const { checkServer, checkDatabase } = require('../controllers/healthController');

const router = express.Router();

router.get('/', checkServer);      // becomes GET /api/health
router.get('/db', checkDatabase);  // becomes GET /api/health/db

module.exports = router;