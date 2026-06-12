const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const actorsController = require('../controllers/actorsController');

const router = express.Router();

router.get('/concepteurs', requireAuth, actorsController.listConcepteurs);
router.post('/concepteurs', requireAuth, requireFleetManager, actorsController.createConcepteur);
// Self-profile routes — must come before /:id to avoid 'me' being treated as an id
router.get('/concepteurs/me', requireAuth, actorsController.getMyConcepteurProfile);
router.patch('/concepteurs/me', requireAuth, actorsController.updateMyConcepteurProfile);
router.get('/concepteurs/:id', requireAuth, actorsController.getConcepteur);
router.put('/concepteurs/:id', requireAuth, requireFleetManager, actorsController.updateConcepteur);

router.get('/technicians', requireAuth, actorsController.listTechnicians);
router.post('/technicians', requireAuth, requireFleetManager, actorsController.createTechnician);
router.put('/technicians/:id', requireAuth, requireFleetManager, actorsController.updateTechnician);
router.get(
    '/maintenance-agents',
    requireAuth,
    actorsController.listMaintenanceAgents,
);

router.post(
    '/maintenance-agents',
    requireAuth,
    requireFleetManager,
    actorsController.createMaintenanceAgent,
);

router.put(
    '/maintenance-agents/:id',
    requireAuth,
    requireFleetManager,
    actorsController.updateMaintenanceAgent,
);

module.exports = router;
