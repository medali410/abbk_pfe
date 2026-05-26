const express = require('express');
const telemetryController = require('../controllers/telemetryController');

const router = express.Router();

router.get('/historique', telemetryController.getLatest);

module.exports = router;
