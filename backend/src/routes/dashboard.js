const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const dashboardController = require('../controllers/dashboardController');

const router = express.Router();

router.get('/kpis', requireAuth, requireFleetManager, dashboardController.kpis);
router.get('/fleet-overview', requireAuth, requireFleetManager, dashboardController.fleetOverview);

module.exports = router;
