const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const machineController = require('../controllers/machineController');

const router = express.Router();

router.get('/', machineController.list);
router.post('/', requireAuth, requireFleetManager, machineController.create);
router.get('/:machineId', machineController.getById);
router.put('/:machineId', requireAuth, requireFleetManager, machineController.update);
router.post('/:machineId/stop', requireAuth, machineController.stop);
router.post('/:machineId/start', requireAuth, machineController.start);
router.post('/:machineId/config', requireAuth, machineController.saveConfigAndPublish);
router.delete('/:machineId', requireAuth, requireFleetManager, machineController.remove);

module.exports = router;
