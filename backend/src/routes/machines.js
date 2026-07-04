const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const machineController = require('../controllers/machineController');
const instanceCtrl = require('../controllers/machineInstanceController');

const router = express.Router();

// ─── Routes modèle machine (catalogue) ───────────────────────────────────────
router.get('/', machineController.list);
router.post('/', requireAuth, requireFleetManager, machineController.create);
router.get('/:machineId', machineController.getById);
router.put('/:machineId', requireAuth, requireFleetManager, machineController.update);
router.post('/:machineId/stop', requireAuth, machineController.stop);
router.post('/:machineId/start', requireAuth, machineController.start);
router.post('/:machineId/config', requireAuth, machineController.saveConfigAndPublish);
router.post('/:machineId/reset_danger', requireAuth, machineController.resetDanger);
router.delete('/:machineId', requireAuth, requireFleetManager, machineController.remove);

// ─── Routes instances physiques (:machineId = modelId) ───────────────────────
router.get('/:machineId/instances', requireAuth, instanceCtrl.listInstancesByModel);

module.exports = router;

