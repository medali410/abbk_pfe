const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const actorsController = require('../controllers/actorsController');

const router = express.Router();

router.get('/concepteurs', requireAuth, requireFleetManager, actorsController.listConcepteurs);
router.post('/concepteurs', requireAuth, requireFleetManager, actorsController.createConcepteur);
// Self-profile routes — must come before /:id to avoid 'me' being treated as an id
router.get('/concepteurs/me', requireAuth, actorsController.getMyConcepteurProfile);
router.patch('/concepteurs/me', requireAuth, actorsController.updateMyConcepteurProfile);
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
