const express = require('express');
const { requireAuth, requireFleetManager } = require('../lib/auth');
const machineController = require('../controllers/machineController');

const router = express.Router();

router.get('/', machineController.list);
router.post('/', requireAuth, requireFleetManager, machineController.create);
router.get('/:machineId', machineController.getById);
router.post('/:machineId/stop', machineController.stop);
router.delete('/:machineId', machineController.remove);

module.exports = router;
