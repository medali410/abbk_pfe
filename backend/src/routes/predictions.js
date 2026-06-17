// ================================================================
// ABBK Backend — src/routes/predictions.js
// ================================================================

const express = require('express');
const router  = express.Router();
const {
  getPredictions,
  getLatestPrediction,
  getCriticalMachines,
  getPredictionStats
} = require('../controllers/predictionController');

// GET /api/predictions/critical
router.get('/critical', getCriticalMachines);

// GET /api/machines/:machineId/predictions
router.get('/machines/:machineId/predictions', getPredictions);

// GET /api/machines/:machineId/predictions/latest
router.get('/machines/:machineId/predictions/latest', getLatestPrediction);

// GET /api/machines/:machineId/predictions/stats
router.get('/machines/:machineId/predictions/stats', getPredictionStats);

module.exports = router;
