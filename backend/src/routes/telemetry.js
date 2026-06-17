const express = require('express');
const telemetryController = require('../controllers/telemetryController');
const predictionController = require('../controllers/predictionController');

const router = express.Router();

router.get('/historique', telemetryController.getLatest);
router.post('/predict', predictionController.predictOnDemand);

module.exports = router;
