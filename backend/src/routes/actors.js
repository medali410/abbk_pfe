const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const actorsController = require('../controllers/actorsController');

const router = express.Router();

router.get('/concepteurs', requireAuth, requireFleetManager, actorsController.listConcepteurs);
router.post('/concepteurs', requireAuth, requireFleetManager, actorsController.createConcepteur);
router.get('/concepteurs/:id', requireAuth, requireFleetManager, actorsController.getConcepteur);
router.put('/concepteurs/:id', requireAuth, requireFleetManager, actorsController.updateConcepteur);

router.get('/technicians', requireAuth, actorsController.listTechnicians);
router.get(
    '/maintenance-agents',
    requireAuth,
    requireFleetManager,
    actorsController.listMaintenanceAgents,
);

module.exports = router;
